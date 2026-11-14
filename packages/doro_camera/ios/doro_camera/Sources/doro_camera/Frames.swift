import AVFoundation
import CoreImage
import CoreMedia
import CoreVideo
import DoroCameraCore
import Foundation

// Frame types shared by the hardware camera and the synthetic camera, so the preview, the Live
// pre-roll buffer, Motion clips and video recording are one code path with two sources.

/// One video frame with its presentation time in seconds (the capture session's clock).
struct VideoFrame {
    let time: Double
    let pixelBuffer: CVPixelBuffer
}

/// A mono 16-bit PCM chunk. Audio is converted to this form at the edge, so Motion clips never depend on
/// what the microphone's native format happens to be.
struct AudioChunk {
    static let sampleRate = 44_100.0

    let time: Double
    let pcm: Data

    var frameCount: Int { pcm.count / 2 }
    var duration: Double { Double(frameCount) / AudioChunk.sampleRate }
}

/// Copies camera frames into a small private pool at reduced size. The camera's own buffer pool is tiny:
/// holding its buffers for seconds (the Live pre-roll) would make the camera drop frames.
final class FrameDownscaler {
    #if targetEnvironment(simulator)
    private let context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: true])
    #else
    private let context = CIContext(options: [.cacheIntermediates: false])
    #endif
    private var pool: CVPixelBufferPool?
    private var poolSize = (width: 0, height: 0)

    /// Scales `source` so its long edge is at most `longEdge`, keeping the aspect ratio. Returns nil if no buffer is available.
    func copy(_ source: CVPixelBuffer, longEdge: Int) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        let scale = min(1.0, Double(longEdge) / Double(max(width, height)))
        let targetWidth = max(2, Int((Double(width) * scale).rounded()) & ~1)
        let targetHeight = max(2, Int((Double(height) * scale).rounded()) & ~1)
        if pool == nil || poolSize.width != targetWidth || poolSize.height != targetHeight {
            let attributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: targetWidth,
                kCVPixelBufferHeightKey as String: targetHeight,
                kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
            ]
            var created: CVPixelBufferPool?
            CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &created)
            pool = created
            poolSize = (targetWidth, targetHeight)
        }
        guard let pool = pool else { return nil }
        var output: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &output) == kCVReturnSuccess, let destination = output else { return nil }
        var image = CIImage(cvPixelBuffer: source)
        if scale < 1 {
            image = image.transformed(by: CGAffineTransform(scaleX: Double(targetWidth) / Double(width), y: Double(targetHeight) / Double(height)))
        }
        context.render(image, to: destination)
        return destination
    }
}

enum AudioConversion {
    /// Converts whatever the microphone delivers (16-bit or float, any channel count, any rate, interleaved or
    /// planar) to mono 16-bit PCM at 44.1 kHz. iOS does not let an AVCaptureAudioDataOutput choose its format
    /// (`audioSettings` is macOS-only), so the conversion happens here.
    static func chunk(from sampleBuffer: CMSampleBuffer) -> AudioChunk? {
        guard CMSampleBufferDataIsReady(sampleBuffer),
              let block = CMSampleBufferGetDataBuffer(sampleBuffer),
              let format = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamPointer = CMAudioFormatDescriptionGetStreamBasicDescription(format) else { return nil }
        let description = streamPointer.pointee
        guard description.mFormatID == kAudioFormatLinearPCM, description.mChannelsPerFrame > 0, description.mSampleRate > 0 else { return nil }

        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == kCMBlockBufferNoErr,
              let base = pointer, length > 0 else { return nil }
        let raw = UnsafeRawPointer(base)

        let channels = Int(description.mChannelsPerFrame)
        let isFloat = (description.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let planar = (description.mFormatFlags & kAudioFormatFlagIsNonInterleaved) != 0
        let bytesPerSample = Int(description.mBitsPerChannel) / 8
        guard bytesPerSample == 2 || bytesPerSample == 4 else { return nil }
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0, length >= frames * bytesPerSample * (planar ? channels : channels) else { return nil }

        func sample(frame: Int, channel: Int) -> Float {
            let index = planar ? channel * frames + frame : frame * channels + channel
            let offset = index * bytesPerSample
            if isFloat, bytesPerSample == 4 {
                return raw.loadUnaligned(fromByteOffset: offset, as: Float.self)
            }
            if bytesPerSample == 2 {
                return Float(raw.loadUnaligned(fromByteOffset: offset, as: Int16.self)) / 32768
            }
            return Float(raw.loadUnaligned(fromByteOffset: offset, as: Int32.self)) / 2_147_483_648
        }

        // mono = average of the channels
        var mono = [Float](repeating: 0, count: frames)
        for frame in 0..<frames {
            var sum: Float = 0
            for channel in 0..<channels { sum += sample(frame: frame, channel: channel) }
            mono[frame] = sum / Float(channels)
        }

        // linear resampling to 44.1 kHz when the microphone runs at another rate
        let ratio = description.mSampleRate / AudioChunk.sampleRate
        let outCount = ratio == 1 ? frames : max(1, Int((Double(frames) / ratio).rounded()))
        var pcm = Data(capacity: outCount * 2)
        for i in 0..<outCount {
            let value: Float
            if ratio == 1 {
                value = mono[i]
            } else {
                let position = Double(i) * ratio
                let lower = min(Int(position), frames - 1)
                let upper = min(lower + 1, frames - 1)
                let fraction = Float(position - Double(lower))
                value = mono[lower] * (1 - fraction) + mono[upper] * fraction
            }
            var int16 = Int16(max(-1, min(1, value)) * 32767)
            withUnsafeBytes(of: &int16) { pcm.append(contentsOf: $0) }
        }
        return AudioChunk(time: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds, pcm: pcm)
    }

    /// Wraps PCM bytes in a sample buffer so AVAssetWriter can encode them to AAC.
    static func sampleBuffer(from chunk: AudioChunk, presentationTime: CMTime) -> CMSampleBuffer? {
        var description = AudioStreamBasicDescription(
            mSampleRate: AudioChunk.sampleRate, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1, mBitsPerChannel: 16, mReserved: 0
        )
        var format: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format
        ) == noErr, let format = format else { return nil }

        var block: CMBlockBuffer?
        let bytes = chunk.pcm
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: bytes.count, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: bytes.count, flags: 0, blockBufferOut: &block
        ) == kCMBlockBufferNoErr, let block = block else { return nil }
        let copied = bytes.withUnsafeBytes { raw -> OSStatus in
            guard let base = raw.baseAddress else { return -1 }
            return CMBlockBufferReplaceDataBytes(with: base, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes.count)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }

        var sample: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: chunk.frameCount,
            presentationTimeStamp: presentationTime, packetDescriptions: nil, sampleBufferOut: &sample
        ) == noErr else { return nil }
        return sample
    }
}
