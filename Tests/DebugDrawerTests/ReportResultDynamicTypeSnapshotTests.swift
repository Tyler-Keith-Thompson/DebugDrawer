// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    @testable import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ReportResultDynamicTypeSnapshotTests {
        @Test("A ready report stays readable at a large accessibility text size")
        func ready() throws {
            let url = URL(fileURLWithPath: "/tmp/Shop-Report-2027-01-15T08-00-00Z.zip")
            let sut = DrawerReportResult(state: .ready(url)) {}
            let renderer = ImageRenderer(content: sut
                .frame(width: 340, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }
    }
#endif
