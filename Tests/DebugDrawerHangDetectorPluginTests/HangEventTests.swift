#if DEBUG
    @testable import DebugDrawerHangDetectorPlugin
    import Foundation
    import Testing

    @Suite
    struct HangEventTests {
        @Test("Durations read in whole milliseconds, rounded down", arguments: [
            (Duration.milliseconds(612), "612 ms"),
            (Duration.zero, "0 ms"),
            (Duration.microseconds(999), "0 ms"),
            (Duration.milliseconds(1250), "1250 ms"),
            (Duration.seconds(20), "20000 ms")
        ])
        func milliseconds(duration: Duration, expected: String) {
            let actual = HangEvent.milliseconds(duration)

            #expect(actual == expected)
        }

        @Test("A hang as text is how long, when and where from, then its frames")
        func text() {
            let sut = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), duration: .milliseconds(612),
                frames: ["0 Example 0x1 block + 4", "1 Example 0x2 main + 8"], source: .detected, isSeen: false
            )
            let expected = """
            Main thread hung for 612 ms
            Date: 2025-11-16T10:46:40Z
            Source: Detected

            0 Example 0x1 block + 4
            1 Example 0x2 main + 8

            """

            let actual = sut.text()

            #expect(actual == expected)
        }

        @Test("A hang with no stack says why in place of the frames")
        func textWithoutStack() {
            let sut = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 0), duration: .seconds(2), frames: [], source: .metricKit, isSeen: true
            )
            let expected = """
            Main thread hung for 2000 ms
            Date: 1970-01-01T00:00:00Z
            Source: MetricKit

            No stack was captured: the main thread got going before the watcher looked.

            """

            let actual = sut.text()

            #expect(actual == expected)
        }
    }
#endif
