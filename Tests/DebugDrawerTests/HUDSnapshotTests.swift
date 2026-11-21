// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS) && canImport(SnapshotTesting)
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

        // An AppKit window with no SwiftUI view: the HUD is drawn in a panel of the drawer's own
        // over it (DrawerChromePanel). Neither is ever shown; each is drawn at 2x and the panel
        // laid over the window where it sits.
        @Test("Over an AppKit window, the HUD's panel draws the pinned readouts at the top leading corner", arguments: [ColorScheme.light, .dark])
        func hudOverTheApp(colorScheme: ColorScheme) throws {
            let suite = "HUDSnapshotTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            drawer.registerGlobal(SnapshotFramesPlugin())
            drawer.hudLayout.pinned = ["DebugDrawerTests.SnapshotFramesPlugin"]
            let appearance = try #require(NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua))
            let title = NSTextField(labelWithString: "Orders")
            title.font = .preferredFont(forTextStyle: .title1)
            let app = NSStackView(views: [title, NSButton(title: "Refresh", target: nil, action: nil)])
            app.orientation = .vertical
            app.alignment = .centerX
            app.translatesAutoresizingMaskIntoConstraints = false
            let content = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 160))
            content.addSubview(app)
            NSLayoutConstraint.activate([
                app.centerXAnchor.constraint(equalTo: content.centerXAnchor),
                app.centerYAnchor.constraint(equalTo: content.centerYAnchor)
            ])
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 320, height: 160),
                styleMask: [.borderless],
                backing: .buffered,
                defer: false
            )
            window.appearance = appearance
            window.contentView = content
            content.layoutSubtreeIfNeeded()
            let panel = DrawerChromePanel(role: .hud, host: window, drawer: drawer)
            panel.appearance = appearance
            defer { window.removeChildWindow(panel) }
            let card = try #require(panel.contentView)
            card.subviews.first?.layoutSubtreeIfNeeded()

            func drawn(_ view: NSView) throws -> NSBitmapImageRep {
                let bitmap = try #require(NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * 2), pixelsHigh: Int(view.bounds.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0
                ))
                bitmap.size = view.bounds.size
                view.cacheDisplay(in: view.bounds, to: bitmap)
                return bitmap
            }
            let windowImage = try drawn(content)
            let cardImage = try drawn(card)
            let actual = NSImage(size: content.bounds.size)
            actual.lockFocus()
            appearance.performAsCurrentDrawingAppearance {
                NSColor.windowBackgroundColor.setFill()
                content.bounds.fill()
            }
            // Laid over what is drawn already: an image rep's plain draw(in:) copies its clear
            // pixels too.
            windowImage.draw(
                in: content.bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
            )
            cardImage.draw(
                in: CGRect(
                    origin: CGPoint(x: panel.frame.minX - window.frame.minX, y: panel.frame.minY - window.frame.minY),
                    size: panel.frame.size
                ),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
            )
            actual.unlockFocus()

            #expect(panel.contentSize.width > 0)
            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
