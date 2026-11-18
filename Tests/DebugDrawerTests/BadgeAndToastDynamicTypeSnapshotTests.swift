// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawer

    private struct SnapshotNoticePlugin: DebugDrawerPlugin {
        var title = "Network"
        var icon = "network"
        var body: some View { EmptyView() }
    }

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct BadgeAndToastDynamicTypeSnapshotTests {
        @Test("A toast stays readable at a large accessibility text size")
        func toast() throws {
            let toast = DebugDrawerToast(pluginID: "SnapshotNoticePlugin", message: "GET /api/orders failed with 500", count: 4)
            let sut = DrawerToastView(toast: toast, plugin: AnyDebugDrawerPlugin(SnapshotNoticePlugin()), open: {}, dismiss: {})
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("A badged section header stays readable at a large accessibility text size")
        func badgedHeader() throws {
            let sut = PluginHeaderLabel(plugin: AnyDebugDrawerPlugin(SnapshotNoticePlugin()), isExpanded: false, isPinned: false, badge: 12)
            let renderer = ImageRenderer(content: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }

        @Test("A silenced section header's crossed-out bell stays readable at a large accessibility text size")
        func silencedHeader() throws {
            let sut = PluginHeaderLabel(plugin: AnyDebugDrawerPlugin(SnapshotNoticePlugin()), isExpanded: false, isPinned: true, isNoticesMuted: true)
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }
    }
#endif
