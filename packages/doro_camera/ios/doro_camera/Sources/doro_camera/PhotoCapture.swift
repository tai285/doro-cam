import AVFoundation
import DoroCameraCore
import Foundation
import ImageIO

/// The files one still capture produced, still in memory.
struct CapturedStill {
    /// The camera's own file (HEIC, JPEG or DNG): saved bit-exact as the original (NFR-005).
    var originalData: Data
    var originalMime: String
    /// A viewable encoding to render the look from. Equals the original unless the original is RAW.
    var renderSource: Data
    var exif: [String: Any]
    var width: Int
    var height: Int
}

/// Runs one `AVCapturePhotoOutput` capture and hands back the encoded data. One instance per capture.
final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, AVCapturePhotoFileDataRepresentationCustomizer {
    private let location: LocationMessage?
    private let format: PhotoFormat
    private var continuation: CheckedContinuation<CapturedStill, Error>?
    private var rawData: Data?
    private var processedData: Data?
    private var exif: [String: Any] = [:]
    private var failure: Error?

    init(location: LocationMessage?, format: PhotoFormat) {
        self.location = location
        self.format = format
    }

    func capture(output: AVCapturePhotoOutput, settings: AVCapturePhotoSettings) async throws -> CapturedStill {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            output.capturePhoto(with: settings, delegate: self)
        }
    }

    // GPS goes into the photo's own metadata so the original stays one lossless file (PRIV-001: only when passed).
    func replacementMetadata(for photo: AVCapturePhoto) -> [String: Any]? {
        guard let location = location else { return nil }
        var metadata = photo.metadata
        var gps: [String: Any] = [
            kCGImagePropertyGPSLatitude as String: abs(location.latitude),
            kCGImagePropertyGPSLatitudeRef as String: location.latitude >= 0 ? "N" : "S",
            kCGImagePropertyGPSLongitude as String: abs(location.longitude),
            kCGImagePropertyGPSLongitudeRef as String: location.longitude >= 0 ? "E" : "W",
        ]
        if let altitude = location.altitudeM {
            gps[kCGImagePropertyGPSAltitude as String] = abs(altitude)
            gps[kCGImagePropertyGPSAltitudeRef as String] = altitude >= 0 ? 0 : 1
        }
        if let accuracy = location.accuracyM {
            gps[kCGImagePropertyGPSHPositioningError as String] = accuracy
        }
        metadata[kCGImagePropertyGPSDictionary as String] = gps
        return metadata
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            failure = error
            return
        }
        guard let data = photo.fileDataRepresentation(with: self) ?? photo.fileDataRepresentation() else {
            failure = CameraError(.captureFailed, "The camera returned no image data.")
            return
        }
        if photo.isRawPhoto {
            rawData = data
        } else {
            processedData = data
            exif = photo.metadata
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        guard let continuation = continuation else { return }
        self.continuation = nil
        if let error = error ?? failure {
            continuation.resume(throwing: (error as? CameraError) ?? CameraError(.captureFailed, "The photo could not be captured."))
            return
        }
        let original: Data
        let mime: String
        if format == .dng, let raw = rawData {
            original = raw
            mime = "image/x-adobe-dng"
        } else if let processed = processedData {
            original = processed
            mime = format == .heif ? "image/heic" : "image/jpeg"
        } else {
            continuation.resume(throwing: CameraError(.captureFailed, "The camera returned no image data."))
            return
        }
        let size = StillRenderer.pixelSize(of: original)
            ?? StillRenderer.pixelSize(of: processedData ?? original)
            ?? (width: Int(resolvedSettings.photoDimensions.width), height: Int(resolvedSettings.photoDimensions.height))
        continuation.resume(
            returning: CapturedStill(
                originalData: original,
                originalMime: mime,
                renderSource: processedData ?? original,
                exif: exif,
                width: size.width,
                height: size.height
            )
        )
    }
}

enum PhotoMetadata {
    /// Overlays what the photo's own EXIF says was used (the truth for this frame) onto the device's current state.
    static func merge(report: AppliedReport, exif: [String: Any]) -> AppliedReport {
        var merged = report
        guard let values = exif[kCGImagePropertyExifDictionary as String] as? [String: Any] else { return merged }
        if let iso = (values[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first {
            merged.iso = iso.intValue
        }
        if let time = (values[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue, time > 0 {
            merged.exposureTimeNs = ExposureMath.nanoseconds(fromSeconds: time)
        }
        if let aperture = (values[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue, aperture > 0 {
            merged.aperture = aperture
        }
        if let equivalent = (values[kCGImagePropertyExifFocalLenIn35mmFilm as String] as? NSNumber)?.doubleValue, equivalent > 0 {
            merged.focalLength35mmEq = equivalent
        }
        if let bias = (values[kCGImagePropertyExifExposureBiasValue as String] as? NSNumber)?.doubleValue {
            merged.exposureBiasEV = bias
        }
        if let flash = (values[kCGImagePropertyExifFlash as String] as? NSNumber)?.intValue {
            merged.flashFired = (flash & 1) == 1
        }
        return merged
    }
}
