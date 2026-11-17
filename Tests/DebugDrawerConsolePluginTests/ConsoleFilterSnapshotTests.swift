// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets. The search
    // field, the segmented picker and the text view are AppKit's, which ImageRenderer draws as
    // placeholders, so the view is hosted in a window that is never shown and drawn into a bitmap
    // at a fixed 2x scale, in the appearance the test asks for. macOS doesn't scale text with
    // Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleFilterSnapshotTests {
        @Test(
            "The filters: a pattern's error, the toolbar, lines with their subsystem and category, and the time range and muted hints",
            arguments: [ColorScheme.light, .dark]
        )
        func filters(colorScheme: ColorScheme) throws {
            // Local wall-clock times, so the HH:mm:ss.SSS timestamps read the same in every time zone.
            let morning = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9, minute: 41)))
            let lines = [
                LogLine(timestamp: morning, text: "App launched", source: .stdout, level: .info),
                LogLine(
                    timestamp: morning.addingTimeInterval(0.25), text: "GET /feed 200", source: .oslog, level: .debug,
                    subsystem: "com.example.feed", category: "networking"
                ),
                LogLine(
                    timestamp: morning.addingTimeInterval(2), text: "Decoding failed: missing key 'id'", source: .oslog, level: .error,
                    subsystem: "com.example.feed", category: "decoding"
                )
            ]
            let sut = VStack(alignment: .leading, spacing: 0) {
                ConsoleSearchField(text: .constant("feed("), isRegularExpression: .constant(true), issue: ConsoleSearch.InvalidPattern()) {
                    ConsoleMoreMenu(
                        timeRange: .constant(.last(minutes: 5)), mutes: [], muteChoices: [], mute: { _ in }, unmute: { _ in }, copyAll: {}
                    )
                }
                ConsoleToolbarView(
                    isFollowing: .constant(true), filterLevel: .constant(.debug),
                    clear: {}
                )
                DebugDrawerCodeBlock {
                    ConsoleTextView(lines: lines, isFollowing: .constant(false))
                        .frame(height: 90)
                }
                ConsoleTimeRangeHint(timeRange: .last(minutes: 5)) {}
                ConsoleMutedHint(count: 12, mutes: [.subsystem("com.example.cart")], isShowing: false, toggle: {}, unmute: { _ in }, unmuteAll: {})
            }
            let host = NSHostingView(rootView: sut
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

            // DD-182: a hosted text field's caret and edge render a few pixels differently from
            // run to run, so 99% of the pixels must match rather than all of them.
            assertSnapshot(of: actual, as: .image(precision: 0.99, perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
