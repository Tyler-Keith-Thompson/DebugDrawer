// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the
    // test asks for. macOS doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DrawerReportResultSnapshotTests {
        @Test("A ready report shows a check, the zip's name, a share button and a dismiss button", arguments: [ColorScheme.light, .dark])
        func ready(colorScheme: ColorScheme) throws {
            let url = URL(fileURLWithPath: "/tmp/Shop-Report-2027-01-15T08-00-00Z.zip")
            let sut = DrawerReportResult(state: .ready(url)) {}
            let renderer = ImageRenderer(content: sut
                .frame(width: 340)
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A failed report shows a warning, the reason and a dismiss button", arguments: [ColorScheme.light, .dark])
        func failed(colorScheme: ColorScheme) throws {
            let sut = DrawerReportResult(state: .failed("The report couldn't be written.")) {}
            let renderer = ImageRenderer(content: sut
                .frame(width: 340)
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
