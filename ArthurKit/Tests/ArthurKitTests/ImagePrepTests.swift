import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import ArthurKit

final class ImagePrepTests: XCTestCase {
    /// A PNG of random pixels (the worst case to compress) or a clear canvas.
    private func png(width: Int, height: Int, noise: Bool) throws -> Data {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        if noise {
            var generator = SystemRandomNumberGenerator()
            for i in pixels.indices {
                pixels[i] = i % 4 == 3 ? 255 : UInt8.random(in: 0...255, using: &generator)
            }
        }
        let image: CGImage = try pixels.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func decode(_ data: Data) throws -> CGImage {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
    }

    func testLargeImageShrinksToFitOneRequest() throws {
        let original = try png(width: 2400, height: 1600, noise: true)
        let jpeg = try ImagePrep.jpegForCraft(original)
        XCTAssertLessThanOrEqual(jpeg.base64EncodedString().count, ImagePrep.craftBase64Limit)
        let image = try decode(jpeg)
        XCTAssertGreaterThanOrEqual(min(image.width, image.height), ImagePrep.craftMinimumSide)

        // The whole request, JSON escaping included, stays under Craft's limit.
        let command = "blocks add --id 00000000-0000-0000-0000-000000000000 --markdown "
            + CraftClient.craftQuote(CraftClient.imageMarkdown(jpeg: jpeg)) + " --position end"
        let body: [String: Any] = ["jsonrpc": "2.0", "id": 1_000_000, "method": "tools/call",
                                   "params": ["name": "craft_write", "arguments": ["command": command]]]
        XCTAssertLessThan(try JSONSerialization.data(withJSONObject: body).count, 100_000)
    }

    func testSmallImageIsNotEnlarged() throws {
        let image = try decode(ImagePrep.jpegForCraft(png(width: 300, height: 150, noise: false)))
        XCTAssertEqual(image.width, 300)
        XCTAssertEqual(image.height, 150)
    }

    func testTransparencyBecomesWhite() throws {
        let image = try decode(ImagePrep.jpegForCraft(png(width: 200, height: 200, noise: false)))
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        XCTAssertGreaterThan(data[0], 250)
        XCTAssertGreaterThan(data[1], 250)
        XCTAssertGreaterThan(data[2], 250)
    }

    func testRejectsTooSmallAndUnreadable() throws {
        XCTAssertThrowsError(try ImagePrep.jpegForCraft(png(width: 500, height: 60, noise: false))) {
            XCTAssertEqual($0 as? ImagePrep.Failure, .tooSmall)
        }
        XCTAssertThrowsError(try ImagePrep.jpegForCraft(Data("not an image".utf8))) {
            XCTAssertEqual($0 as? ImagePrep.Failure, .unreadable)
        }
    }
}
