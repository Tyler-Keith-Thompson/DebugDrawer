// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerViewInspectorPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ViewInspectorDynamicTypeSnapshotTests {
        @Test("The render counts stay readable at a large accessibility text size")
        func renderCounts() throws {
            let rendered = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let entries = [
                RenderTracker.Entry(id: "FeedView", count: 24, lastRender: rendered),
                RenderTracker.Entry(id: "AvatarView", count: 7, lastRender: rendered),
                RenderTracker.Entry(id: "SettingsView", count: 2, lastRender: rendered)
            ]
            let sut = RenderCountList(entries: entries)
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("A hierarchy row stays readable at a large accessibility text size")
        func hierarchyRow() throws {
            let node = ViewNode(
                className: "NSButton", frame: CGRect(x: 0, y: 0, width: 88, height: 32),
                accessibilityLabel: "Save", accessibilityRole: "AXButton", isHidden: false, alpha: 0.5,
                hasClipping: true, cornerRadius: 6, backgroundColor: "#0A84FF", constraintCount: 4,
                subviewCount: 0, children: []
            )
            let sut = ViewNodeRow(node: node, depth: 0, filter: "")
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }
    }
#endif
