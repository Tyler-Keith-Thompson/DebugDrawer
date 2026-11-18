// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import AppKit
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

        // The drawer's overlay holds an NSViewRepresentable, which ImageRenderer draws as a
        // placeholder, so this hosts the app in a window that is never shown and draws it at 2x.
        // Synchronous: the shared drawer is changed and restored in one main-actor turn.
        @Test("With the drawer closed, the app's drawer modifier draws the pinned HUD over the app", arguments: [ColorScheme.light, .dark])
        func hudOverTheApp(colorScheme: ColorScheme) throws {
            let drawer = DebugDrawer.shared
            let previous = drawer.hudLayout
            let wasOpen = drawer.isOpen
            drawer.isOpen = false
            drawer.registerGlobal(SnapshotFramesPlugin())
            drawer.hudLayout = HUDLayout()
            drawer.hudLayout.pinned = ["DebugDrawerTests.SnapshotFramesPlugin"]
            let app = VStack(spacing: 12) {
                Text("Orders").font(.title)
                Button("Refresh") {}
            }
            .frame(width: 320, height: 160)
            .background(.background)
            .debugDrawer()
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let host = NSHostingView(rootView: app)
            host.frame = NSRect(x: 0, y: 0, width: 320, height: 160)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 640, pixelsHigh: 320, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            drawer.hudLayout = previous
            drawer.unregisterGlobal(id: "DebugDrawerTests.SnapshotFramesPlugin")
            drawer.isOpen = wasOpen
            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
