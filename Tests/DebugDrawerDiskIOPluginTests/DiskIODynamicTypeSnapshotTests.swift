// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerDiskIOPlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DiskIODynamicTypeSnapshotTests {
        @Test("Event rows stay readable at a large accessibility text size")
        func rows() throws {
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
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
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background)
                .environment(\.dynamicTypeSize, .accessibility3))
            renderer.scale = 2

            let actual = try #require(renderer.uiImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "accessibility3")
        }
    }
#endif
