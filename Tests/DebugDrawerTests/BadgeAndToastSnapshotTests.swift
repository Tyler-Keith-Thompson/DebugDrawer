// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing

    private struct SnapshotNoticePlugin: DebugDrawerPlugin {
        var title = "Network"
        var icon = "network"
        var body: some View { EmptyView() }
    }

    // ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the
    // test asks for. macOS doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct BadgeAndToastSnapshotTests {
        @Test("A toast shows the plugin's icon and title, its latest message, the count and a dismiss button", arguments: [ColorScheme.light, .dark])
        func toast(colorScheme: ColorScheme) throws {
            let toast = DebugDrawerToast(pluginID: "SnapshotNoticePlugin", message: "GET /api/orders failed with 500", count: 4)
            let sut = DrawerToastView(toast: toast, plugin: AnyDebugDrawerPlugin(SnapshotNoticePlugin()), open: {}, dismiss: {})
            let renderer = ImageRenderer(content: sut
                .frame(width: 344)
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A section header shows its badge count before the chevron", arguments: [ColorScheme.light, .dark])
        func badgedHeader(colorScheme: ColorScheme) throws {
            let sut = PluginHeaderLabel(plugin: AnyDebugDrawerPlugin(SnapshotNoticePlugin()), isExpanded: false, isPinned: false, badge: 12)
            let renderer = ImageRenderer(content: sut
                .frame(width: 320)
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A silenced plugin's header shows a crossed-out bell after its pin, 316 pt wide", arguments: [ColorScheme.light, .dark])
        func silencedHeader(colorScheme: ColorScheme) throws {
            let plugin = AnyDebugDrawerPlugin(SnapshotNoticePlugin())
            let sut = PluginHeaderLabel(plugin: plugin, isExpanded: false, isPinned: true, isNoticesMuted: true)
            let renderer = ImageRenderer(content: sut
                .frame(width: 316)
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
