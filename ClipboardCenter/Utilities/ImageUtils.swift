import AppKit
import CoreGraphics

// MARK: - ImageUtils
// Utility for efficient image thumbnail generation.
// Uses CGImageSource for memory-efficient downsampling rather than
// loading the full-resolution image into memory.

enum ImageUtils {

    /// Generates a thumbnail from an NSImage, constrained to maxSize on its longest edge.
    ///
    /// - Parameters:
    ///   - image: The source image
    ///   - maxSize: Maximum dimension (width or height) in points
    /// - Returns: PNG data of the thumbnail, or nil on failure
    static func generateThumbnail(from image: NSImage, maxSize: CGFloat) -> Data? {
        return autoreleasepool {
            // Convert NSImage to data first, then use CGImageSource for efficient downsampling.
            // This avoids holding the full-resolution NSImage in memory during the resize.
            guard let tiffData = image.tiffRepresentation else { return nil }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxSize * 2, // 2x for Retina
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
            ]

            guard let source = CGImageSourceCreateWithData(tiffData as CFData, nil),
                  let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                // Fallback: manual resize if CGImageSource fails
                return manualResize(image: image, maxSize: maxSize)
            }

            // Convert CGImage back to PNG data
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            return bitmapRep.representation(using: .png, properties: [
                .compressionFactor: 0.8
            ])
        }
    }

    /// Fallback manual resize when CGImageSource isn't available.
    private static func manualResize(image: NSImage, maxSize: CGFloat) -> Data? {
        return autoreleasepool {
            let originalSize = image.size
            guard originalSize.width > 0, originalSize.height > 0 else { return nil }

            let scale: CGFloat
            if originalSize.width > originalSize.height {
                scale = maxSize / originalSize.width
            } else {
                scale = maxSize / originalSize.height
            }

            let targetSize = NSSize(
                width: originalSize.width * scale,
                height: originalSize.height * scale
            )

            let resizedImage = NSImage(size: targetSize, flipped: false) { rect in
                image.draw(in: rect)
                return true
            }

            guard let tiffData = resizedImage.tiffRepresentation,
                  let bitmapRep = NSBitmapImageRep(data: tiffData) else {
                return nil
            }

            return bitmapRep.representation(using: .png, properties: [:])
        }
    }
}
