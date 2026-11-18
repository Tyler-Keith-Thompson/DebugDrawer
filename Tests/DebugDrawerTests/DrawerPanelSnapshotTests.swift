// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing

    // The panel holds text fields and buttons, so it is hosted in a window that is never shown and
    // drawn into a bitmap at a fixed 2x scale, in the appearance the test asks for. macOS doesn't
    // scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DrawerPanelSnapshotTests {
        @Test("The drawer with several plugins open, in every v3 row type, under its header, tabs and filter bar",
              arguments: [ColorScheme.light, .dark])
        func panel(colorScheme: ColorScheme) throws {
            let sut = DrawerFixturePanel()
                .frame(width: 316)
            let host = NSHostingView(rootView: sut)
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
