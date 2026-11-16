// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing

    private struct SnapshotFramesPlugin: DebugDrawerPlugin {
        var title = "Frames"
        var icon = "gauge"
        var body: some View { EmptyView() }
        var hud: Text? { Text("58 FPS  182 MB").font(.caption.monospaced()) }
    }

    private struct SnapshotRequestsPlugin: DebugDrawerPlugin {
        var title = "Requests"
        var icon = "network"
        var body: some View { EmptyView() }
        var hud: Text? { Text("3 in flight").font(.caption.monospaced()) }
    }

    // ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the
    // test asks for. macOS doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct HUDSnapshotTests {
        @Test("The HUD card lists the pinned readouts in order at its default corner", arguments: [ColorScheme.light, .dark])
        func card(colorScheme: ColorScheme) throws {
            let sut = DrawerHUDView(
                readouts: [AnyDebugDrawerPlugin(SnapshotFramesPlugin()), AnyDebugDrawerPlugin(SnapshotRequestsPlugin())],
                origin: nil,
                move: { _ in },
                unpin: { _ in }
            )
            let renderer = ImageRenderer(content: sut
                .frame(width: 240, height: 90)
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
