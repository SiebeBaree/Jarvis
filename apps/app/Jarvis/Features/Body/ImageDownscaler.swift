import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Cross-platform (CoreGraphics-only) downscale + JPEG re-encode for photo
/// uploads: longest side capped, EXIF orientation baked in.
enum ImageDownscaler {
    /// Returns JPEG data with the longest side ≤ `maxPixelSize`, or nil when
    /// the input can't be decoded as an image.
    static func jpegData(
        from data: Data,
        maxPixelSize: Int = 2000,
        quality: Double = 0.82,
    ) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, // bake in orientation
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
        else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil,
        ) else { return nil }

        let encodeOptions: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
        CGImageDestinationAddImage(destination, image, encodeOptions as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
