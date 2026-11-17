#if DEBUG
    import CoreGraphics
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    /// Mockups generated for the tests, so no image file is checked in: data only, no assertions.
    enum MockupFixture {
        /// A PNG `width` by `height` pixels: a light background, a title bar, a block standing for
        /// a button, and three rows, laid out in proportion to its size.
        static func png(width: Int, height: Int) -> Data {
            guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return Data() }
            let unitX = CGFloat(width) / 100
            let unitY = CGFloat(height) / 100
            // Core Graphics draws from the bottom-left; the mockup is laid out from the top, in
            // hundredths of its width and height.
            func fill(_ color: CGColor, _ rect: CGRect) {
                context.setFillColor(color)
                context.fill(CGRect(x: rect.minX * unitX, y: (100 - rect.maxY) * unitY, width: rect.width * unitX, height: rect.height * unitY))
            }
            fill(CGColor(srgbRed: 0.95, green: 0.95, blue: 0.97, alpha: 1), CGRect(x: 0, y: 0, width: 100, height: 100))
            fill(CGColor(srgbRed: 0.20, green: 0.45, blue: 0.95, alpha: 1), CGRect(x: 0, y: 0, width: 100, height: 14))
            fill(CGColor(srgbRed: 0.95, green: 0.30, blue: 0.45, alpha: 1), CGRect(x: 10, y: 22, width: 40, height: 10))
            for row in 0 ..< 3 {
                fill(CGColor(srgbRed: 0.80, green: 0.82, blue: 0.86, alpha: 1), CGRect(x: 10, y: 40 + CGFloat(row) * 14, width: 80, height: 8))
            }
            guard let image = context.makeImage() else { return Data() }
            let data = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return Data() }
            CGImageDestinationAddImage(destination, image, nil)
            CGImageDestinationFinalize(destination)
            return data as Data
        }
    }
#endif
