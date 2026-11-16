// What recording costs the thread that sends an event. The log exists in debug builds only, so it
// is measured there; `--config=release` builds this target without it, and runs
// ReleaseRecordTests instead.
#if DEBUG
    @testable import DebugDrawerAnalyticsPlugin
    import Foundation
    import Testing

    // record runs on the app's own threads, wherever it sends an event, so it must cost about as
    // much as appending to an array. 100,000 events of five properties into a full log of 1,000
    // take a few tens of milliseconds on an Apple silicon Mac in debug builds; the bound is
    // several times that, so a loaded machine passes and a change that copies or sorts the ring on
    // each record (100,000 × 1,000 moves) fails.
    @Suite(.timeLimit(.minutes(1)))
    struct AnalyticsEventLogSpeedTests {
        @Test("Recording 100,000 events into a full log of 1,000 takes under 500 ms, and reading it under 5 ms")
        func recordIntoFullLog() throws {
            let sut = AnalyticsEventLog(capacity: 1000)
            let properties: [String: AnalyticsValue] = ["plan": "pro", "seats": 3, "total": 29.99, "trial": false, "items": ["sku-1", "sku-2"]]
            let clock = ContinuousClock()

            let recordTime = clock.measure {
                for index in 0 ..< 100_000 {
                    sut.record(name: "event_\(index)", properties: properties, source: "Segment")
                }
            }
            var events: [AnalyticsEvent] = []
            let readTime = clock.measure {
                events = sut.events
            }

            print("Analytics: recording 100,000 events takes \(recordTime); reading 1,000 back \(readTime)")
            #expect(events.count == 1000)
            #expect(try #require(events.first).name == "event_99999")
            #expect(recordTime < .milliseconds(500))
            #expect(readTime < .milliseconds(5))
        }
    }
#endif
