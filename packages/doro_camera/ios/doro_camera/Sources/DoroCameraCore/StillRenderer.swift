import Foundation

#if canImport(CoreImage) && canImport(ImageIO)
import CoreGraphics
import CoreImage
import ImageIO

// Pixel work for the derived images of a Memory (ADR-0004, docs/architecture/media-pipeline.md).
// It lives in the core, not the Flutter glue, because CoreImage and ImageIO also exist on macOS, so
// `swift test` can check real pixels on a Mac runner. The ORIGINAL is never touched here (PRF-002).

public struct RenderParameters: Equatable, Sendable {
    /// Packed RGB cube, `lutSize`^3 entries, red varying fastest, 3 bytes per entry. nil = identity.
    public var lut: [UInt8]?
    public var lutSize: Int?
    public var grain: Double
    public var vignette: Double
    /// Target aspect ratio `width:height`; the image is center-cropped to it (CAM-044). nil = keep.
    public var aspect: (width: Int, height: Int)?
    public var jpegQuality: Double

    public init(
        lut: [UInt8]? = nil,
        lutSize: Int? = nil,
        grain: Double = 0,
        vignette: Double = 0,
        aspect: (width: Int, height: Int)? = nil,
        jpegQuality: Double = 0.92
    ) {
        self.lut = lut
        self.lutSize = lutSize
        self.grain = grain
        self.vignette = vignette
        self.aspect = aspect
        self.jpegQuality = jpegQuality
    }

    public static func == (lhs: RenderParameters, rhs: RenderParameters) -> Bool {
        lhs.lut == rhs.lut && lhs.lutSize == rhs.lutSize && lhs.grain == rhs.grain && lhs.vignette == rhs.vignette
            && lhs.aspect?.width == rhs.aspect?.width && lhs.aspect?.height == rhs.aspect?.height && lhs.jpegQuality == rhs.jpegQuality
    }
}

public struct RenderedImage: Sendable {
    public let jpeg: Data
    public let width: Int
    public let height: Int

    public init(jpeg: Data, width: Int, height: Int) {
        self.jpeg = jpeg
        self.width = width
        self.height = height
    }
}

public enum StillRenderer {
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Parses `W:H` such as `3:2`. nil for anything else, so a bad value never crops silently.
    public static func parseAspect(_ text: String?) -> (width: Int, height: Int)? {
        guard let text = text else { return nil }
        let parts = text.split(separator: ":")
        guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 else { return nil }
        return (w, h)
    }

    /// The center crop rectangle for an image of the given size. The ratio is flipped for portrait images
    /// so "3:2" means "the long side over the short side" whichever way the photo was held.
    public static func cropRect(width: Double, height: Double, aspect: (width: Int, height: Int)) -> CGRect {
        var target = Double(aspect.width) / Double(aspect.height)
        if height > width, target > 1 { target = 1 / target }
        if width > height, target < 1 { target = 1 / target }
        let current = width / height
        if abs(current - target) < 1e-6 { return CGRect(x: 0, y: 0, width: width, height: height) }
        if current > target {
            let newWidth = (height * target).rounded(.down)
            return CGRect(x: ((width - newWidth) / 2).rounded(.down), y: 0, width: newWidth, height: height)
        }
        let newHeight = (width / target).rounded(.down)
        return CGRect(x: 0, y: ((height - newHeight) / 2).rounded(.down), width: width, height: newHeight)
    }

    /// Builds the 3D color cube data (RGBA floats) CoreImage expects from packed RGB bytes. nil when the size does not match.
    public static func cubeData(lut: [UInt8], size: Int) -> Data? {
        guard size >= 2, size <= 64, lut.count == size * size * size * 3 else { return nil }
        var floats = [Float](repeating: 1, count: size * size * size * 4)
        for i in 0..<(size * size * size) {
            floats[i * 4] = Float(lut[i * 3]) / 255
            floats[i * 4 + 1] = Float(lut[i * 3 + 1]) / 255
            floats[i * 4 + 2] = Float(lut[i * 3 + 2]) / 255
        }
        return floats.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    /// Applies the look to an encoded photo and returns a JPEG. Orientation is baked into the pixels.
    public static func render(source: Data, parameters: RenderParameters) throws -> RenderedImage {
        guard var image = CIImage(data: source, options: [.applyOrientationProperty: true]) else {
            throw CameraError(.captureFailed, "The photo could not be decoded for rendering.")
        }
        let extent = image.extent
        if let aspect = parameters.aspect {
            let crop = cropRect(width: Double(extent.width), height: Double(extent.height), aspect: aspect)
            image = image.cropped(to: CGRect(x: extent.minX + crop.minX, y: extent.minY + crop.minY, width: crop.width, height: crop.height))
        }
        let box = image.extent

        if let lut = parameters.lut, let size = parameters.lutSize, let data = cubeData(lut: lut, size: size),
           let filter = CIFilter(name: "CIColorCube") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(size, forKey: "inputCubeDimension")
            filter.setValue(data, forKey: "inputCubeData")
            image = filter.outputImage ?? image
        }
        if parameters.vignette > 0, let filter = CIFilter(name: "CIVignette") {
            filter.setValue(image, forKey: kCIInputImageKey)
            filter.setValue(min(max(parameters.vignette, 0), 1) * 2, forKey: kCIInputIntensityKey)
            filter.setValue(1.5, forKey: kCIInputRadiusKey)
            image = filter.outputImage ?? image
        }
        if parameters.grain > 0, let noise = CIFilter(name: "CIRandomGenerator")?.outputImage {
            let strength = CGFloat(min(max(parameters.grain, 0), 1)) * 0.25
            let grain = noise
                .cropped(to: box)
                .applyingFilter(
                    "CIColorMatrix",
                    parameters: [
                        "inputRVector": CIVector(x: strength, y: 0, z: 0, w: 0),
                        "inputGVector": CIVector(x: 0, y: strength, z: 0, w: 0),
                        "inputBVector": CIVector(x: 0, y: 0, z: strength, w: 0),
                        "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
                        "inputBiasVector": CIVector(x: -strength / 2, y: -strength / 2, z: -strength / 2, w: 1),
                    ]
                )
            image = grain.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: image]).cropped(to: box)
        }

        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let quality = min(max(parameters.jpegQuality, 0.1), 1)
        let options: [CIImageRepresentationOption: Any] = [
            CIImageRepresentationOption(rawValue: kCGImageDestinationLossyCompressionQuality as String): quality,
        ]
        guard let jpeg = context.jpegRepresentation(of: image, colorSpace: colorSpace, options: options) else {
            throw CameraError(.captureFailed, "The rendered photo could not be encoded.")
        }
        return RenderedImage(jpeg: jpeg, width: Int(box.width), height: Int(box.height))
    }

    /// A JPEG whose longer side is at most `longEdge` pixels (thumbnail 512, display 2048). Never upscales.
    public static func downscale(source: Data, longEdge: Int, quality: Double = 0.85) throws -> RenderedImage {
        guard let imageSource = CGImageSourceCreateWithData(source as CFData, nil) else {
            throw CameraError(.captureFailed, "The photo could not be read for thumbnails.")
        }
        // Never upscale: a small image keeps its own size.
        let original = pixelSize(of: source)
        let maxEdge = original.map { Swift.min(longEdge, Swift.max($0.width, $0.height)) } ?? longEdge
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxEdge,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
            throw CameraError(.captureFailed, "A thumbnail could not be created.")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else {
            throw CameraError(.captureFailed, "A thumbnail could not be encoded.")
        }
        CGImageDestinationAddImage(destination, thumbnail, [kCGImageDestinationLossyCompressionQuality: min(max(quality, 0.1), 1)] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw CameraError(.captureFailed, "A thumbnail could not be encoded.")
        }
        return RenderedImage(jpeg: output as Data, width: thumbnail.width, height: thumbnail.height)
    }

    /// Pixel size of an encoded image without decoding it fully.
    public static func pixelSize(of data: Data) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}

#endif
