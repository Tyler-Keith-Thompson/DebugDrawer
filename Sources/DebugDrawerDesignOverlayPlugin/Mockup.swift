#if DEBUG
    import CoreGraphics
    import Foundation
    import ImageIO

    /// A mockup, decoded: the image the overlay draws and the data it was decoded from, which is
    /// what is saved.
    struct Mockup: @unchecked Sendable {
        // @unchecked: CGImage is immutable, and Data is a value.

        /// The image, turned upright as its orientation says (a photo of a phone's screen, say).
        let image: CGImage
        /// The data the image was decoded from.
        let data: Data

        /// Decodes `data`, in any format Image I/O reads.
        ///
        /// - Throws: `MockupFailure.notAnImage` when `data` holds no image.
        init(data: Data) throws(MockupFailure) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil), CGImageSourceGetCount(source) > 0,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int
            else { throw .notAnImage }
            // A thumbnail as large as the image is the image with its orientation applied, which
            // CGImageSourceCreateImageAtIndex leaves to the caller.
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw .notAnImage }
            self.image = image
            self.data = data
        }

        /// The image's size in pixels, upright.
        var pixelSize: CGSize {
            CGSize(width: image.width, height: image.height)
        }
    }
#endif
