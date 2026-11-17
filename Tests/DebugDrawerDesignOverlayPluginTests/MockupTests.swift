#if DEBUG
    import CoreGraphics
    @testable import DebugDrawerDesignOverlayPlugin
    import Foundation
    import ImageIO
    import Testing
    import UniformTypeIdentifiers

    @Suite
    struct MockupTests {
        @Test("A PNG decodes to its pixel size, keeping the data it came from")
        func png() throws {
            let data = MockupFixture.png(width: 120, height: 260)
            let expected = CGSize(width: 120, height: 260)

            let actual = try Mockup(data: data)

            #expect(actual.pixelSize == expected)
            #expect(actual.data == data)
        }

        @Test("A one-pixel image decodes")
        func onePixel() throws {
            let data = MockupFixture.png(width: 1, height: 1)

            let actual = try Mockup(data: data)

            #expect(actual.pixelSize == CGSize(width: 1, height: 1))
        }

        @Test("A JPEG whose orientation says it was turned a quarter is decoded upright, its width and height swapped")
        func orientation() throws {
            let png = MockupFixture.png(width: 200, height: 100)
            let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            let jpeg = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(jpeg, UTType.jpeg.identifier as CFString, 1, nil))
            // 6: the stored image must be turned 90° clockwise to be upright.
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyOrientation: 6] as CFDictionary)
            #expect(CGImageDestinationFinalize(destination))
            let expected = CGSize(width: 100, height: 200)

            let actual = try Mockup(data: jpeg as Data)

            #expect(actual.pixelSize == expected)
        }

        @Test("Data that isn't an image throws notAnImage, and so does no data")
        func notAnImage() {
            #expect(throws: MockupFailure.notAnImage) { try Mockup(data: Data("not an image".utf8)) }
            #expect(throws: MockupFailure.notAnImage) { try Mockup(data: Data()) }
        }

        @Test("A PNG cut off after its header throws notAnImage")
        func truncated() {
            let data = MockupFixture.png(width: 50, height: 50).prefix(40)

            #expect(throws: MockupFailure.notAnImage) { try Mockup(data: Data(data)) }
        }
    }
#endif
