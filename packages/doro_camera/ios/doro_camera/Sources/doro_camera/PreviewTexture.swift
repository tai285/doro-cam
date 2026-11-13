import CoreVideo
import Flutter
import Foundation

/// The live preview as a Flutter texture. The camera thread publishes the newest frame; the raster
/// thread takes it. Only the latest frame matters, so older ones are simply replaced.
final class PreviewTexture: NSObject, FlutterTexture {
    private let lock = NSLock()
    private var latest: CVPixelBuffer?
    private weak var registry: FlutterTextureRegistry?
    private(set) var textureId: Int64 = 0

    init(registry: FlutterTextureRegistry) {
        self.registry = registry
        super.init()
        textureId = registry.register(self)
    }

    func publish(_ buffer: CVPixelBuffer) {
        lock.lock()
        latest = buffer
        lock.unlock()
        registry?.textureFrameAvailable(textureId)
    }

    /// The newest frame, also used to take a still when the synthetic source is active.
    func currentFrame() -> CVPixelBuffer? {
        lock.lock()
        defer { lock.unlock() }
        return latest
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer = latest else { return nil }
        return Unmanaged.passRetained(buffer)
    }

    func dispose() {
        registry?.unregisterTexture(textureId)
        lock.lock()
        latest = nil
        lock.unlock()
    }
}
