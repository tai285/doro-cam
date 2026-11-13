import XCTest
@testable import DoroCameraCore

#if canImport(CoreImage) && canImport(ImageIO)
import CoreGraphics
import ImageIO

final class StillRendererTests: XCTestCase {
    /// A solid-color JPEG of a given size, built with ImageIO so no fixture file is needed.
    private func solidJPEG(width: Int, height: Int, red: UInt8, green: UInt8, blue: UInt8) throws -> Data {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(red: CGFloat(red) / 255, green: CGFloat(green) / 255, blue: CGFloat(blue) / 255, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = context.makeImage()!
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 1.0] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func centerPixel(of jpeg: Data) -> (r: Int, g: Int, b: Int)? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: -(image.width / 2), y: -(image.height / 2), width: image.width, height: image.height))
        return (Int(pixel[0]), Int(pixel[1]), Int(pixel[2]))
    }

    // [CAM-044]
    func testParseAspect() {
        XCTAssertEqual(StillRenderer.parseAspect("3:2")?.width, 3)
        XCTAssertEqual(StillRenderer.parseAspect("3:2")?.height, 2)
        XCTAssertNil(StillRenderer.parseAspect(nil))
        XCTAssertNil(StillRenderer.parseAspect("wide"))
        XCTAssertNil(StillRenderer.parseAspect("0:2"))
        XCTAssertNil(StillRenderer.parseAspect("3:2:1"))
    }

    // [CAM-044] the crop is centered and never larger than the image
    func testCropRectCentersAndRespectsOrientation() {
        let landscape = StillRenderer.cropRect(width: 4000, height: 3000, aspect: (16, 9))
        XCTAssertEqual(landscape.width, 4000)
        XCTAssertEqual(landscape.height, 2250)
        XCTAssertEqual(landscape.minY, 375)
        let portrait = StillRenderer.cropRect(width: 3000, height: 4000, aspect: (16, 9))
        XCTAssertEqual(portrait.width, 2250) // 16:9 held upright is 9:16: the long side stays whole
        XCTAssertEqual(portrait.height, 4000)
        XCTAssertEqual(portrait.minX, 375)
        let square = StillRenderer.cropRect(width: 4000, height: 3000, aspect: (1, 1))
        XCTAssertEqual(square.width, 3000)
        XCTAssertEqual(square.minX, 500)
        let same = StillRenderer.cropRect(width: 3000, height: 2000, aspect: (3, 2))
        XCTAssertEqual(same, CGRect(x: 0, y: 0, width: 3000, height: 2000))
    }

    func testCubeDataRequiresAMatchingLut() {
        XCTAssertNil(StillRenderer.cubeData(lut: [0, 0, 0], size: 2))
        XCTAssertNil(StillRenderer.cubeData(lut: [], size: 1))
        let lut = [UInt8](repeating: 255, count: 2 * 2 * 2 * 3)
        XCTAssertEqual(StillRenderer.cubeData(lut: lut, size: 2)?.count, 2 * 2 * 2 * 4 * MemoryLayout<Float>.size)
    }

    // [PRF-003] rendering produces a JPEG of the right size, and the original bytes are untouched
    func testRenderKeepsSizeWithoutALookAndNeverModifiesTheSource() throws {
        let source = try solidJPEG(width: 160, height: 120, red: 200, green: 100, blue: 50)
        let copy = source
        let rendered = try StillRenderer.render(source: source, parameters: RenderParameters())
        XCTAssertEqual(rendered.width, 160)
        XCTAssertEqual(rendered.height, 120)
        XCTAssertEqual(source, copy)
        let size = StillRenderer.pixelSize(of: rendered.jpeg)
        XCTAssertEqual(size?.width, 160)
        XCTAssertEqual(size?.height, 120)
    }

    // [CAM-044] only the rendition is cropped
    func testRenderCropsToTheAspectRatio() throws {
        let source = try solidJPEG(width: 160, height: 120, red: 10, green: 10, blue: 10)
        let rendered = try StillRenderer.render(source: source, parameters: RenderParameters(aspect: (1, 1)))
        XCTAssertEqual(rendered.width, 120)
        XCTAssertEqual(rendered.height, 120)
    }

    // [PRF-001] an inverting LUT really changes the pixels (parity of the look, within JPEG tolerance)
    func testLutChangesColors() throws {
        let source = try solidJPEG(width: 64, height: 64, red: 255, green: 0, blue: 0)
        let size = 2
        var lut = [UInt8]()
        for b in 0..<size { for g in 0..<size { for r in 0..<size { // red fastest
            lut += [UInt8(255 - r * 255), UInt8(255 - g * 255), UInt8(255 - b * 255)]
        } } }
        let rendered = try StillRenderer.render(source: source, parameters: RenderParameters(lut: lut, lutSize: size))
        let pixel = try XCTUnwrap(centerPixel(of: rendered.jpeg))
        XCTAssertLessThan(pixel.r, 40)
        XCTAssertGreaterThan(pixel.g, 215)
        XCTAssertGreaterThan(pixel.b, 215)
    }

    // [PRF-006]
    func testGrainAndVignetteChangeTheImageButKeepItDecodable() throws {
        let source = try solidJPEG(width: 96, height: 96, red: 128, green: 128, blue: 128)
        let plain = try StillRenderer.render(source: source, parameters: RenderParameters())
        let effects = try StillRenderer.render(source: source, parameters: RenderParameters(grain: 0.8, vignette: 0.8))
        XCTAssertEqual(effects.width, 96)
        XCTAssertNotEqual(plain.jpeg, effects.jpeg)
        XCTAssertNotNil(centerPixel(of: effects.jpeg))
    }

    func testRenderRejectsData() {
        XCTAssertThrowsError(try StillRenderer.render(source: Data([1, 2, 3]), parameters: RenderParameters())) { error in
            XCTAssertEqual((error as? CameraError)?.code, .captureFailed)
        }
        XCTAssertThrowsError(try StillRenderer.downscale(source: Data([1, 2, 3]), longEdge: 64))
        XCTAssertNil(StillRenderer.pixelSize(of: Data([1, 2, 3])))
    }

    // media-pipeline: thumbnail long edge 512, display 2048; never upscale
    func testDownscaleLimitsTheLongEdgeAndNeverUpscales() throws {
        let source = try solidJPEG(width: 2000, height: 1000, red: 1, green: 2, blue: 3)
        let thumbnail = try StillRenderer.downscale(source: source, longEdge: 512)
        XCTAssertEqual(max(thumbnail.width, thumbnail.height), 512)
        XCTAssertEqual(thumbnail.width, 512)
        XCTAssertEqual(thumbnail.height, 256)
        let small = try solidJPEG(width: 100, height: 50, red: 1, green: 2, blue: 3)
        let same = try StillRenderer.downscale(source: small, longEdge: 512)
        XCTAssertEqual(max(same.width, same.height), 100) // not enlarged
        XCTAssertEqual(StillRenderer.pixelSize(of: thumbnail.jpeg)?.width, 512)
    }
}

#endif
