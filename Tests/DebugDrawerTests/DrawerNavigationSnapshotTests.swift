// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS) && canImport(SnapshotTesting)
    import AppKit
    @testable import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing

    // The panels hold text fields and buttons, so each is hosted in a window that is never shown
    // and drawn into a bitmap at a fixed 2x scale, in the appearance the test asks for. A plugin
    // shown alone fills the panel's height, so each is drawn at a fixed size: the drawer's 316
    // point width, and a window's height. macOS doesn't scale text with Dynamic Type, so the Mac
    // pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DrawerNavigationSnapshotTests {
        @Test("A plugin shown alone: the back button, the jump bar ending at the plugin, its heading and its body at full height",
              arguments: [ColorScheme.light, .dark])
        func detail(colorScheme: ColorScheme) throws {
            let size = CGSize(width: 316, height: 520)
            let host = NSHostingView(rootView: DrawerFixtureDetailPanel().frame(width: size.width, height: size.height))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("The compact panel: a list of the plugins, each header a row that shows its plugin alone",
              arguments: [ColorScheme.light, .dark])
        func compact(colorScheme: ColorScheme) throws {
            let size = CGSize(width: 316, height: 420)
            let host = NSHostingView(rootView: DrawerFixtureCompactPanel().frame(width: size.width, height: size.height))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: size)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
