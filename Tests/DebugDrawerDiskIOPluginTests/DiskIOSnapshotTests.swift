// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerDiskIOPlugin

    // ImageRenderer draws the view without a window, at a fixed scale, in the color scheme the
    // test asks for, so a snapshot doesn't depend on the Mac's own appearance or display. macOS
    // doesn't scale text with Dynamic Type, so the Mac pins light and dark only.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOSnapshotTests {
        @Test(
            "Event rows show the operation, a main-thread warning, the path's end, the size and the duration",
            arguments: [ColorScheme.light, .dark]
        )
        func rows(colorScheme: ColorScheme) throws {
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
                .environment(\.colorScheme, colorScheme))
            renderer.scale = 2

            let actual = try #require(renderer.nsImage)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
