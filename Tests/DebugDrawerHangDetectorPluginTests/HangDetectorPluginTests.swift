#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerHangDetectorPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct HangDetectorPluginTests {
        @Test("The plugin is Hangs, in the Performance category, and adds to bug reports")
        func identity() {
            let sut = HangDetectorPlugin(store: HangStore(threshold: .milliseconds(250)))

            #expect(sut.id == "HangDetectorPlugin")
            #expect(sut.title == "Hangs")
            #expect(sut.category == "Performance")
            #expect(sut.icon == "hourglass")
            #expect(AnyDebugDrawerPlugin(sut).contributesToReport)
        }

        @Test("The drawer's search offers clearing the hangs, found by \"main thread\" too")
        func action() throws {
            let store = HangStore(threshold: .milliseconds(250))
            store.add(HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(300), frames: [], source: .detected, isSeen: false
            ))
            let sut = HangDetectorPlugin(store: store)

            let actual = try #require(sut.actions.first)
            actual.perform()

            #expect(sut.actions.map(\.title) == ["Clear hangs"])
            #expect(actual.keywords.contains("main thread"))
            #expect(store.events.isEmpty)
        }

        @Test("The bug report gets every hang, newest first, in hangs.txt under the threshold")
        func report() throws {
            let events = [
                HangEvent(
                    id: UUID(), date: Date(timeIntervalSince1970: 1_763_290_000), duration: .milliseconds(612),
                    frames: ["0 Example 0x1 block + 4"], source: .detected, isSeen: false
                ),
                HangEvent(
                    id: UUID(), date: Date(timeIntervalSince1970: 0), duration: .seconds(2), frames: [], source: .metricKit, isSeen: true
                )
            ]
            let expected = """
            Threshold: 250 ms

            Main thread hung for 612 ms
            Date: 2025-11-16T10:46:40Z
            Source: Detected

            0 Example 0x1 block + 4

            Main thread hung for 2000 ms
            Date: 1970-01-01T00:00:00Z
            Source: MetricKit

            No stack was captured: the main thread got going before the watcher looked.

            """
            var actual = DebugDrawerReport()

            HangDetectorPlugin.contribute(events, threshold: .milliseconds(250), to: &actual)

            #expect(actual.files.map(\.name) == ["hangs.txt"])
            #expect(String(bytes: try #require(actual.files.first).data, encoding: .utf8) == expected)
        }

        @Test("No hangs add nothing to the bug report")
        func reportEmpty() {
            var actual = DebugDrawerReport()

            HangDetectorPlugin.contribute([], threshold: .milliseconds(250), to: &actual)

            #expect(actual.files.isEmpty)
        }

        @Test("The default threshold is a quarter of a second")
        func defaultThreshold() {
            let actual = HangDetector.defaultThreshold

            #expect(actual == .milliseconds(250))
        }
    }
#endif
