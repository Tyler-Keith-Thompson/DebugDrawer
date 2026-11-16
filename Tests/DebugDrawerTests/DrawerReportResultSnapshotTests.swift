// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawer
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the
    // test asks for. macOS doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DrawerReportResultSnapshotTests {
        @Test("A ready report shows a check, the zip's name, a share button and a dismiss button", arguments: [ColorScheme.light, .dark])
        func ready(colorScheme: ColorScheme) throws {
            let url = URL(fileURLWithPath: "/tmp/Shop-Report-2027-01-15T08-00-00Z.zip")
            let sut = DrawerReportResult(state: .ready(url)) {}
            let renderer = ImageRenderer(content: sut
                .frame(width: 340)
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("With an uploader a ready report also shows a send button", arguments: [ColorScheme.light, .dark])
        func readyToSend(colorScheme: ColorScheme) throws {
            let url = URL(fileURLWithPath: "/tmp/Shop-Report-2027-01-15T08-00-00Z.zip")
            let sut = DrawerReportResult(state: .ready(url), send: { _ in }, dismiss: {})
            let renderer = ImageRenderer(content: sut
                .frame(width: 340)
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        // The progress bar is AppKit's, which ImageRenderer draws as a placeholder, so the view is
        // hosted in a window that is never shown and drawn into a bitmap at 2x.
        @Test("A report being sent shows the percentage, a progress bar and the zip's name, and no buttons", arguments: [ColorScheme.light, .dark])
        func uploading(colorScheme: ColorScheme) throws {
            let url = URL(fileURLWithPath: "/tmp/Shop-Report-2027-01-15T08-00-00Z.zip")
            let sut = DrawerReportResult(state: .uploading(url, progress: 0.4), send: { _ in }, dismiss: {})
            let host = NSHostingView(rootView: sut
                .frame(width: 340)
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

        @Test("A failed upload shows a warning, the uploader's message, and retry, share and dismiss buttons", arguments: [ColorScheme.light, .dark])
        func uploadFailed(colorScheme: ColorScheme) throws {
            let url = URL(fileURLWithPath: "/tmp/Shop-Report-2027-01-15T08-00-00Z.zip")
            let sut = DrawerReportResult(state: .uploadFailed(url, reason: "The server is down for maintenance."), send: { _ in }, dismiss: {})
            let renderer = ImageRenderer(content: sut
                .frame(width: 340)
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A sent report shows a check, the zip's name, and share and dismiss buttons", arguments: [ColorScheme.light, .dark])
        func sent(colorScheme: ColorScheme) throws {
            let url = URL(fileURLWithPath: "/tmp/Shop-Report-2027-01-15T08-00-00Z.zip")
            let sut = DrawerReportResult(state: .sent(url), send: { _ in }, dismiss: {})
            let renderer = ImageRenderer(content: sut
                .frame(width: 340)
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A failed report shows a warning, the reason and a dismiss button", arguments: [ColorScheme.light, .dark])
        func failed(colorScheme: ColorScheme) throws {
            let sut = DrawerReportResult(state: .failed("The report couldn't be written.")) {}
            let renderer = ImageRenderer(content: sut
                .frame(width: 340)
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
