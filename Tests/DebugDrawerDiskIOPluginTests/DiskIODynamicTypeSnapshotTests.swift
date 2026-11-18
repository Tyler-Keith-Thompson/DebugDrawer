// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import SnapshotTesting
    import SwiftUI
    import Testing

    // At 316 points, the width of the drawer on an iPad and the narrowest it gets, at the default
    // text size and an accessibility one. ImageRenderer draws the view without a window, at a
    // fixed scale and width, so the reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DiskIODynamicTypeSnapshotTests {
        @Test(
            "In an iPad's drawer, event rows stay readable, a failure's error and a copy's destination included",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func rows(size: DynamicTypeSize) throws {
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
                .environment(\.dynamicTypeSize, size))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(size)")
        }

        @Test(
            "In an iPad's drawer, the totals stay readable, the main-thread and failure counts included",
            arguments: [DynamicTypeSize.large, .accessibility3]
        )
        func totals(size: DynamicTypeSize) throws {
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
                .environment(\.dynamicTypeSize, size))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(size)")
        }
    }
#endif
