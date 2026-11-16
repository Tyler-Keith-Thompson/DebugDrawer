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
        @Test("The render counts list each view type with an OK, warning or error glyph by count", arguments: [ColorScheme.light, .dark])
        func renderCounts(colorScheme: ColorScheme) throws {
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
                .environment(\.colorScheme, colorScheme))
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
