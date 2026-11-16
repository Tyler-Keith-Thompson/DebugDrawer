// iOS scales text with Dynamic Type, so the large-text snapshots run on the iOS simulator.
#if os(iOS)
    import SnapshotTesting
    import SwiftUI
    import Testing
    @testable import DebugDrawerConsolePlugin

    // ImageRenderer draws the view without a window, at a fixed scale and width, so the
    // reference doesn't depend on which simulator runs it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleDynamicTypeSnapshotTests {
        @Test("The console's lines stay readable at a large accessibility text size")
        func lines() throws {
            // Local wall-clock times, so the HH:mm:ss.SSS timestamps read the same in every time zone.
            let morning = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 5, hour: 9, minute: 41)))
            let lines = [
                LogLine(timestamp: morning, text: "App launched", source: .stdout, level: .info),
                LogLine(timestamp: morning.addingTimeInterval(0.25), text: "Fetching feed", source: .oslog, level: .debug),
                LogLine(timestamp: morning.addingTimeInterval(1.5), text: "Feed is stale; serving cache", source: .oslog, level: .notice),
                LogLine(timestamp: morning.addingTimeInterval(2), text: "Decoding failed: missing key 'id'", source: .stderr, level: .error)
            ]
            let sut = ConsoleTextView(lines: lines, isFollowing: .constant(false)).frame(height: 120)
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
