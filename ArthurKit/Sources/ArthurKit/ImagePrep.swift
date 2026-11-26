import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Shrinks an image until it fits in one Craft request. Borrowed from
/// Maverick: Craft's command set has no upload, so the image travels inline as
/// a `data:` URL, which Craft imports and re-hosts. The original is untouched.
public enum ImagePrep {
    public enum Failure: Error, Equatable {
        /// Not image data ImageIO can read.
        case unreadable
        /// Craft rejects images under 100 px on a side.
        case tooSmall
        /// Still over the limit at the smallest size and quality tried.
        case tooLarge
    }

    /// Craft refuses request bodies around 100KB (measured in Maverick:
    /// 100,000 base64 characters works, 115,000 gets HTTP 413). This leaves
    /// headroom for the request wrapper and JSON escaping.
    public static let craftBase64Limit = 94_000
    public static let craftMinimumSide = 100

    /// A JPEG of `original` whose base64 form is at most `maxBase64Characters`,
    /// stepping the longest edge and then the quality down until it fits.
    /// Transparent areas (a window screenshot's shadow) become white.
    public static func jpegForCraft(_ original: Data,
                                    maxBase64Characters: Int = craftBase64Limit) throws -> Data {
        guard let source = CGImageSourceCreateWithData(original as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { throw Failure.unreadable }
        guard min(width, height) >= craftMinimumSide else { throw Failure.tooSmall }

        for edge in [1920, 1600, 1400, 1250, 1100, 900, 720, 560, 420, 320, 240] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: edge,
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
                  min(thumbnail.width, thumbnail.height) >= craftMinimumSide,
                  let image = flattened(thumbnail)
            else { continue }
            for quality in [0.7, 0.6, 0.5, 0.4] {
                guard let jpeg = encodeJPEG(image, quality: quality) else { continue }
                if (jpeg.count + 2) / 3 * 4 <= maxBase64Characters { return jpeg }
            }
        }
        throw Failure.tooLarge
    }

    /// Draws onto white: JPEG has no transparency and would otherwise turn
    /// clear pixels black.
    private static func flattened(_ image: CGImage) -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fill(rect)
        context.draw(image, in: rect)
        return context.makeImage()
    }

    private static func encodeJPEG(_ image: CGImage, quality: Double) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        let properties: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
