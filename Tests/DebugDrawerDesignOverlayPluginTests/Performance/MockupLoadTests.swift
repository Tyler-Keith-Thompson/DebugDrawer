// What reading the saved mockup at install costs. The plugin exists in debug builds only, so it is
// measured there; `--config=release` builds this target without it, and runs ReleaseInstallTests
// instead.
#if DEBUG
    import CoreGraphics
    @testable import DebugDrawerDesignOverlayPlugin
    import Foundation
    import ImageIO
    import Testing
    import UniformTypeIdentifiers

    // install reads the saved mockup on the main actor, before the app's first frame, so it must
    // cost little next to a launch. A 13-inch iPad's screen at @2x (2064 by 2752 pixels), drawn
    // with a stripe in every row so PNG can't squeeze it to nothing, is read and decoded in about
    // 20 ms on an Apple silicon Mac in a debug build. The bound is seven times that, so a loaded
    // machine passes, and a change that decodes it several times over, or a row at a time, fails.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct MockupLoadTests {
        @Test("Reading and decoding a saved 2064 by 2752 PNG mockup at install takes under 150 ms")
        func loadCost() throws {
            let width = 2064
            let height = 2752
            let context = try #require(CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            for row in 0 ..< height {
                context.setFillColor(CGColor(srgbRed: CGFloat(row % 7) / 7, green: CGFloat(row % 13) / 13, blue: CGFloat(row % 29) / 29, alpha: 1))
                context.fill(CGRect(x: (row * 37) % width, y: row, width: width / 3, height: 1))
            }
            let image = try #require(context.makeImage())
            let data = NSMutableData()
            let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
            CGImageDestinationAddImage(destination, image, nil)
            #expect(CGImageDestinationFinalize(destination))
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let folder = MockupFolder(directory: directory)
            try folder.saveMockup(data as Data)
            let loads = 10
            let clock = ContinuousClock()
            var sizes: [CGSize] = []

            let time = clock.measure {
                for _ in 0 ..< loads {
                    let sut = DesignOverlayModel(storage: folder)
                    sut.load()
                    if let mockup = sut.mockup { sizes.append(mockup.pixelSize) }
                }
            }

            let perLoad = time / loads
            print("Design Overlay: loading a 2064x2752 mockup takes \(perLoad)")
            #expect(sizes == Array(repeating: CGSize(width: width, height: height), count: loads))
            #expect(perLoad < .milliseconds(150))
        }
    }
#endif
