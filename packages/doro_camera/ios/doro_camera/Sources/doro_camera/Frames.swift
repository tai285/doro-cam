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
    private let context = CIContext(options: [.cacheIntermediates: false])
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
    /// The settings that make AVCaptureAudioDataOutput deliver mono 16-bit interleaved PCM at 44.1 kHz.
    static let captureSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: AudioChunk.sampleRate,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ]

    /// Extracts PCM bytes from a delivered audio sample buffer.
    static func chunk(from sampleBuffer: CMSampleBuffer) -> AudioChunk? {
        guard CMSampleBufferDataIsReady(sampleBuffer), let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == kCMBlockBufferNoErr,
              let base = pointer, length > 0 else { return nil }
        return AudioChunk(time: CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds, pcm: Data(bytes: base, count: length))
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
