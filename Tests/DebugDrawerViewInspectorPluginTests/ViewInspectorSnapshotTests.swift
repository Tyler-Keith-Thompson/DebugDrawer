// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerViewInspectorPlugin

    // ImageRenderer draws AppKit-backed controls (text fields, pickers, switches, disclosure
    // groups) as placeholders, so a test of a view holding one hosts it in a window that is never
    // shown and draws it into a bitmap at a fixed 2x scale, in the appearance the test asks for:
    // the snapshot doesn't depend on the Mac's own appearance or display. Views without one use
    // ImageRenderer. macOS doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ViewInspectorSnapshotTests {
        @Test("The render counts list each tracked view with a glyph by count, under their total", arguments: [ColorScheme.light, .dark])
        func renderCounts(colorScheme: ColorScheme) throws {
            let entries = [
                RenderTracker.Entry(id: "FeedView", count: 24),
                RenderTracker.Entry(id: "AvatarView", count: 7),
                RenderTracker.Entry(id: "SettingsView", count: 2)
            ]
            let sut = RenderCountList(entries: entries) {}
            // 316 pt: the drawer's narrowest panel. The Reset button is AppKit's, so the list is
            // hosted rather than drawn by ImageRenderer.
            let host = NSHostingView(rootView: VStack(spacing: 0) { sut }
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("The overlay outlines views by depth, with the grid over its view and a ripple at a click", arguments: [ColorScheme.light, .dark])
        func overlayDrawing(colorScheme: ColorScheme) throws {
            // A sample layout, as the app would draw it, with the overlay over it.
            let card = CGRect(x: 16, y: 16, width: 284, height: 96)
            let avatar = CGRect(x: 28, y: 28, width: 40, height: 40)
            let title = CGRect(x: 80, y: 32, width: 140, height: 16)
            let button = CGRect(x: 16, y: 128, width: 284, height: 44)
            let outlines = [
                ViewOutline(frame: CGRect(x: 0, y: 0, width: 316, height: 188), depth: 0),
                ViewOutline(frame: card, depth: 1),
                ViewOutline(frame: avatar, depth: 2),
                ViewOutline(frame: title, depth: 2),
                ViewOutline(frame: button, depth: 1)
            ]
            let sut = ZStack(alignment: .topLeading) {
                Rectangle().fill(.background)
                ForEach([card, button], id: \.minY) { rect in
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.quaternary)
                        .frame(width: rect.width, height: rect.height)
                        .offset(x: rect.minX, y: rect.minY)
                }
                InspectorOverlayDrawing(
                    outlines: outlines,
                    grids: [button],
                    gridStyle: GridStyle(spacing: 8, color: .blue, opacity: 0.3),
                    ripples: [],
                    rippleDidFinish: { _ in }
                )
                // A ripple as it first appears: ImageRenderer would run the ripple's animation
                // to its end, so the mark is drawn at its start rather than through `ripples`.
                RippleMark(progress: 0)
                    .position(x: 120, y: 150)
            }
            .frame(width: 316, height: 188)
            .environment(\.colorScheme, colorScheme)
            let renderer = ImageRenderer(content: sut)
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A hierarchy row shows the class, size and flags of a view", arguments: [ColorScheme.light, .dark])
        func hierarchyRow(colorScheme: ColorScheme) throws {
            let node = ViewNode(
                className: "NSButton", frame: NSRect(x: 0, y: 0, width: 88, height: 32),
                accessibilityLabel: "Save", accessibilityRole: "AXButton", isHidden: false, alpha: 0.5,
                hasClipping: true, cornerRadius: 6, backgroundColor: "#0A84FF", constraintCount: 4,
                subviewCount: 0, children: []
            )
            let sut = ViewNodeRow(node: node, depth: 0, filter: "")
            let host = NSHostingView(rootView: sut
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
