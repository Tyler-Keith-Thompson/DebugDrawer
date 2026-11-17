// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerConsolePlugin

    // The text view is AppKit's, which ImageRenderer draws as a placeholder, so it is hosted in a
    // window that is never shown and drawn into a bitmap at a fixed 2x scale, in the appearance the
    // test asks for. macOS doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleMetadataSnapshotTests {
        @Test(
            "A line from the app's logger shows its source and text, then its metadata as quiet key=value fields, at the drawer's width",
            arguments: [ColorScheme.light, .dark]
        )
        func metadata(colorScheme: ColorScheme) throws {
            // Local wall-clock times, so the HH:mm:ss.SSS timestamps read the same in every time zone.
            let morning = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9, minute: 41)))
            let lines = [
                LogLine(
                    timestamp: morning, text: "Checkout started", source: .sink, level: .info, subsystem: "com.example.shop", category: "checkout"
                ),
                LogLine(
                    timestamp: morning.addingTimeInterval(1.5), text: "Payment declined", source: .sink, level: .error,
                    subsystem: "com.example.shop", category: "checkout", metadata: ["order": "1042", "card": "visa", "user": "7"]
                ),
                LogLine(timestamp: morning.addingTimeInterval(2), text: "Feed loaded", source: .oslog, level: .info, subsystem: "com.example.feed")
            ]
            let sut = ConsoleTextView(lines: lines, isFollowing: .constant(false))
            let host = NSHostingView(rootView: sut.frame(height: 100)
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
    }
#endif
