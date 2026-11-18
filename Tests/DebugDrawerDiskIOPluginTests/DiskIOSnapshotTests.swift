// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets. ImageRenderer
    // draws the view without a window, at a fixed scale, in the color scheme the test asks for, so
    // a snapshot doesn't depend on the Mac's own appearance or display. macOS doesn't scale text
    // with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOSnapshotTests {
        @Test(
            "Event rows show the operation, main-thread and failure glyphs, the error, the path, a copy's destination, the size and the duration",
            arguments: [ColorScheme.light, .dark]
        )
        func rows(colorScheme: ColorScheme) throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let missing = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileNoSuchFile.rawValue, userInfo: [
                NSLocalizedDescriptionKey: "“old.json” couldn’t be removed because it doesn’t exist."
            ])
            let events = [
                IOEvent(
                    timestamp: start, operation: .read, path: "/Users/ada/Library/Caches/Example/feed.json",
                    size: 48_213, duration: 0.024, isMainThread: true
                ),
                IOEvent(
                    timestamp: start, operation: .write, path: "/Users/ada/Documents/Example/draft.txt",
                    size: 512, duration: 0.002, isMainThread: false
                ),
                IOEvent(
                    timestamp: start, operation: .create, path: "/Users/ada/Documents/Example/Exports",
                    size: 0, duration: 0.001, isMainThread: false
                ),
                IOEvent(
                    timestamp: start, operation: .copy, path: "/Users/ada/Documents/Example/draft.txt",
                    destination: "/Users/ada/Documents/Example/Exports/draft copy.txt", size: 0, duration: 0.003, isMainThread: false
                ),
                IOEvent(
                    timestamp: start, operation: .delete, path: "/Users/ada/Library/Caches/Example/old.json",
                    size: 0, duration: 0.001, isMainThread: true, error: missing
                ),
                IOEvent(
                    timestamp: start, operation: .list, path: "/Users/ada/Documents/Example",
                    size: 14, duration: 0.001, isMainThread: false
                )
            ]
            let sut = VStack(spacing: 0) {
                ForEach(events) { event in
                    IOEventRow(event: event)
                }
            }
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test(
            "Totals show the reads, writes and their bytes, with a warning for main-thread calls and an error for failed ones",
            arguments: [ColorScheme.light, .dark]
        )
        func totals(colorScheme: ColorScheme) throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let failure = NSError(domain: NSCocoaErrorDomain, code: CocoaError.fileNoSuchFile.rawValue)
            var totals = DiskIOTotals()
            for event in [
                IOEvent(timestamp: start, operation: .read, path: "/a", size: 48_213, duration: 0, isMainThread: true),
                IOEvent(timestamp: start, operation: .read, path: "/b", size: 1_200_000, duration: 0, isMainThread: false),
                IOEvent(timestamp: start, operation: .write, path: "/c", size: 512, duration: 0, isMainThread: true),
                IOEvent(timestamp: start, operation: .delete, path: "/d", size: 0, duration: 0, isMainThread: false, error: failure)
            ] {
                totals.add(event)
            }
            let sut = DiskIOTotalsRows(totals: totals)
            let renderer = ImageRenderer(content: sut
                .frame(width: 316, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
