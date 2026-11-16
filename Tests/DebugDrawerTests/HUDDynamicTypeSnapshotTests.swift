// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawer

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

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct HUDDynamicTypeSnapshotTests {
        @Test("The HUD card stays readable at a large accessibility text size")
        func card() throws {
            // The HUD places its card inside the space it is given, so the frame has a height too.
            let sut = DrawerHUDView(
                readouts: [AnyDebugDrawerPlugin(SnapshotFramesPlugin()), AnyDebugDrawerPlugin(SnapshotRequestsPlugin())],
                origin: nil,
                move: { _ in },
                unpin: { _ in }
            )
            .frame(height: 160)
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
