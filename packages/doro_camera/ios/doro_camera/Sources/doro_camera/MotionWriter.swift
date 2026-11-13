import AVFoundation
import CoreMedia
import DoroCameraCore
import Foundation

struct WrittenClip {
    let width: Int
    let height: Int
    let durationSeconds: Double
    let hasAudio: Bool
    let bytes: Int64
}

private func videoSettings(width: Int, height: Int, fps: Double) -> [String: Any] {
    [
        AVVideoCodecKey: AVVideoCodecType.h264,
        AVVideoWidthKey: width,
        AVVideoHeightKey: height,
        AVVideoCompressionPropertiesKey: [
            AVVideoAverageBitRateKey: max(1_000_000, width * height * 3),
            AVVideoMaxKeyFrameIntervalKey: max(1, Int(fps.rounded())),
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
        ],
    ]
}

private let aacSettings: [String: Any] = [
    AVFormatIDKey: kAudioFormatMPEG4AAC,
    AVSampleRateKey: AudioChunk.sampleRate,
    AVNumberOfChannelsKey: 1,
    AVEncoderBitRateKey: 64_000,
]

private func bufferAttributes(width: Int, height: Int) -> [String: Any] {
    [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width,
        kCVPixelBufferHeightKey as String: height,
    ]
}

/// Clockwise degrees to rotate upright-portrait frames so the clip is upright for the way the phone was held.
func clipRotationDegrees(for orientation: DeviceOrientation) -> Int {
    (orientation.rotationDegrees - 90 + 360) % 360
}

private func transform(rotationDegrees: Int) -> CGAffineTransform {
    CGAffineTransform(rotationAngle: CGFloat(rotationDegrees) * .pi / 180)
}

/// Encodes the buffered video and audio around the shutter into one MP4 (H.264 + AAC, ADR-0005).
/// Writes to `<final>.partial` and renames when complete, so a killed app never leaves a half clip (NFR-002).
enum MotionClipWriter {
    static func write(
        video: [VideoFrame],
        audio: [AudioChunk],
        startTime: Double,
        output: AtomicOutput,
        rotationDegrees: Int
    ) async throws -> WrittenClip {
        guard let first = video.first else {
            throw CameraError(.captureFailed, "There were no frames to build the Motion Memory from.")
        }
        let width = CVPixelBufferGetWidth(first.pixelBuffer)
        let height = CVPixelBufferGetHeight(first.pixelBuffer)
        let span = max(0.001, (video.last?.time ?? first.time) - first.time)
        let fps = Double(video.count - 1) / span

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    output.discard()
                    let writer = try AVAssetWriter(outputURL: output.partialURL, fileType: .mp4)
                    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings(width: width, height: height, fps: video.count > 1 ? fps : 15))
                    videoInput.expectsMediaDataInRealTime = false
                    videoInput.transform = transform(rotationDegrees: rotationDegrees)
                    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: bufferAttributes(width: width, height: height))
                    guard writer.canAdd(videoInput) else { throw CameraError(.captureFailed, "The clip could not be set up.") }
                    writer.add(videoInput)

                    var audioInput: AVAssetWriterInput?
                    if !audio.isEmpty {
                        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
                        input.expectsMediaDataInRealTime = false
                        if writer.canAdd(input) {
                            writer.add(input)
                            audioInput = input
                        }
                    }
                    guard writer.startWriting() else { throw writer.error ?? CameraError(.captureFailed, "The clip could not be started.") }
                    writer.startSession(atSourceTime: .zero)

                    func waitUntilReady(_ input: AVAssetWriterInput) throws {
                        var waited = 0.0
                        while !input.isReadyForMoreMediaData {
                            if writer.status == .failed { throw writer.error ?? CameraError(.captureFailed, "The clip could not be written.") }
                            Thread.sleep(forTimeInterval: 0.002)
                            waited += 0.002
                            if waited > 10 { throw CameraError(.captureFailed, "Writing the clip timed out.") }
                        }
                    }

                    // Interleave by time so the container keeps audio and video in step.
                    var v = 0
                    var a = 0
                    var lastVideoTime = CMTime.zero
                    while v < video.count || a < audio.count {
                        let nextVideo = v < video.count ? video[v].time : Double.infinity
                        let nextAudio = a < audio.count ? audio[a].time : Double.infinity
                        if nextVideo <= nextAudio, v < video.count {
                            let frame = video[v]
                            v += 1
                            let time = CMTime(seconds: max(0, frame.time - startTime), preferredTimescale: 600)
                            try waitUntilReady(videoInput)
                            if !adaptor.append(frame.pixelBuffer, withPresentationTime: time) {
                                throw writer.error ?? CameraError(.captureFailed, "A frame could not be written.")
                            }
                            lastVideoTime = time
                        } else if a < audio.count, let input = audioInput {
                            let chunk = audio[a]
                            a += 1
                            if chunk.time + chunk.duration <= startTime { continue } // ended before the clip starts
                            let time = CMTime(seconds: max(0, chunk.time - startTime), preferredTimescale: 44_100)
                            if let sample = AudioConversion.sampleBuffer(from: chunk, presentationTime: time) {
                                try waitUntilReady(input)
                                if !input.append(sample) { throw writer.error ?? CameraError(.captureFailed, "Audio could not be written.") }
                            }
                        } else {
                            a += 1
                        }
                    }
                    videoInput.markAsFinished()
                    audioInput?.markAsFinished()
                    writer.finishWriting {
                        if writer.status == .completed {
                            do {
                                try output.commit()
                                let size = (try? FileManager.default.attributesOfItem(atPath: output.finalURL.path)[.size] as? NSNumber)?.int64Value ?? 0
                                continuation.resume(returning: WrittenClip(width: width, height: height, durationSeconds: lastVideoTime.seconds, hasAudio: audioInput != nil, bytes: size))
                            } catch {
                                continuation.resume(throwing: error)
                            }
                        } else {
                            output.discard()
                            continuation.resume(throwing: writer.error ?? CameraError(.captureFailed, "The clip could not be finished."))
                        }
                    }
                } catch {
                    output.discard()
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Records video in real time, fed frame by frame from the capture queue (VID-001).
final class VideoRecorder {
    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let audioInput: AVAssetWriterInput?
    private let output: AtomicOutput
    private var started = false
    private var firstTime = 0.0
    private var lastTime = 0.0
    let width: Int
    let height: Int
    var outputPath: String { output.finalURL.path }

    init(output: AtomicOutput, width: Int, height: Int, fps: Int, audio: Bool, rotationDegrees: Int) throws {
        output.discard()
        // Built with locals first: a class instance cannot be used before all its properties are set.
        let writer = try AVAssetWriter(outputURL: output.partialURL, fileType: .mp4)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings(width: width, height: height, fps: Double(fps)))
        videoInput.expectsMediaDataInRealTime = true
        videoInput.transform = transform(rotationDegrees: rotationDegrees)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: bufferAttributes(width: width, height: height))
        guard writer.canAdd(videoInput) else { throw CameraError(.unsupportedConfiguration, "This video size is not supported.") }
        writer.add(videoInput)
        var audioInput: AVAssetWriterInput?
        if audio {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: aacSettings)
            input.expectsMediaDataInRealTime = true
            if writer.canAdd(input) {
                writer.add(input)
                audioInput = input
            }
        }
        guard writer.startWriting() else { throw writer.error ?? CameraError(.captureFailed, "Recording could not start.") }
        self.output = output
        self.width = width
        self.height = height
        self.writer = writer
        self.videoInput = videoInput
        self.adaptor = adaptor
        self.audioInput = audioInput
    }

    var hasAudio: Bool { audioInput != nil }

    func append(_ frame: VideoFrame) {
        if !started {
            writer.startSession(atSourceTime: CMTime(seconds: frame.time, preferredTimescale: 600))
            started = true
            firstTime = frame.time
        }
        guard videoInput.isReadyForMoreMediaData, writer.status == .writing else { return } // drop the frame rather than stall the camera
        if adaptor.append(frame.pixelBuffer, withPresentationTime: CMTime(seconds: frame.time, preferredTimescale: 600)) {
            lastTime = frame.time
        }
    }

    func append(_ chunk: AudioChunk) {
        guard started, let input = audioInput, input.isReadyForMoreMediaData, writer.status == .writing, chunk.time >= firstTime else { return }
        if let sample = AudioConversion.sampleBuffer(from: chunk, presentationTime: CMTime(seconds: chunk.time, preferredTimescale: 44_100)) {
            input.append(sample)
        }
    }

    func finish() async throws -> WrittenClip {
        guard started else {
            writer.cancelWriting()
            output.discard()
            throw CameraError(.captureFailed, "No video was recorded.")
        }
        videoInput.markAsFinished()
        audioInput?.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            output.discard()
            throw writer.error ?? CameraError(.captureFailed, "The video could not be finished.")
        }
        try output.commit()
        let size = (try? FileManager.default.attributesOfItem(atPath: output.finalURL.path)[.size] as? NSNumber)?.int64Value ?? 0
        return WrittenClip(width: width, height: height, durationSeconds: max(0, lastTime - firstTime), hasAudio: audioInput != nil, bytes: size)
    }
}
