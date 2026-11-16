#if DEBUG
    import CoreGraphics

    /// A bitmap's bytes, for comparing two images pixel by pixel. It doesn't own the bytes: whoever
    /// made it keeps their buffer alive while it is used.
    struct BitmapPixels {
        let bytes: UnsafeMutablePointer<UInt8>
        let width: Int
        let height: Int
        let bytesPerPixel: Int
        let bytesPerRow: Int

        fileprivate func offset(column: Int, row: Int) -> Int {
            row * bytesPerRow + column * bytesPerPixel
        }

        fileprivate func contains(column: Int, row: Int) -> Bool {
            column < width && row < height
        }

        /// Whether the red, green and blue of the pixel at `column`, `row` are each within
        /// `tolerance` of `other`'s.
        fileprivate func matches(_ other: BitmapPixels, column: Int, row: Int, tolerance: Int) -> Bool {
            let mine = offset(column: column, row: row)
            let theirs = other.offset(column: column, row: row)
            return (0 ..< 3).allSatisfy { channel in
                abs(Int(bytes[mine + channel]) - Int(other.bytes[theirs + channel])) <= tolerance
            }
        }

        fileprivate func clear(column: Int, row: Int) {
            let start = offset(column: column, row: row)
            for channel in 0 ..< bytesPerPixel {
                bytes[start + channel] = 0
            }
        }
    }

    /// The 3D view debugger's layer diff: a view's snapshot keeps only the pixels that differ from
    /// its parent's, so each layer shows what that view adds.
    enum PixelDiff {
        /// Per-channel tolerance: high, to catch sub-pixel text anti-aliasing.
        static let tolerance = 32

        /// An sRGB context with premultiplied RGBA, 4 bytes a pixel.
        static func rgbaContext(width: Int, height: Int) -> CGContext? {
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
            return CGContext(
                data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        }

        /// The bytes of a context from `rgbaContext(width:height:)`.
        static func pixels(of context: CGContext) -> BitmapPixels? {
            guard let bytes = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
            return BitmapPixels(
                bytes: bytes, width: context.width, height: context.height,
                bytesPerPixel: 4, bytesPerRow: context.bytesPerRow
            )
        }

        /// Makes every pixel of `image` that matches `background` transparent.
        ///
        /// - Returns: How many pixels differ from the background (all of them without one).
        /// - Complexity: O(*width* × *height*).
        static func clearMatching(_ image: BitmapPixels, against background: BitmapPixels?) -> Int {
            var unique = 0
            for row in 0 ..< image.height {
                for column in 0 ..< image.width {
                    if let background, background.contains(column: column, row: row),
                       image.matches(background, column: column, row: row, tolerance: tolerance) {
                        image.clear(column: column, row: row)
                    } else {
                        unique += 1
                    }
                }
            }
            return unique
        }

        /// Whether so few pixels differ (under 0.5%) that the layer adds nothing worth showing.
        static func isNegligible(unique: Int, width: Int, height: Int) -> Bool {
            unique <= width * height / 200
        }
    }
#endif
