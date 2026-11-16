#if DEBUG
    @testable import DebugDrawerAnalyticsPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AnalyticsEventsModelTests {
        @Test("The model starts with the events the log already keeps, newest first, all unseen")
        func initialRead() {
            let log = AnalyticsEventLog(capacity: 10)
            log.record(name: "launched", properties: [:], source: nil)
            log.record(name: "opened", properties: [:], source: nil)
            var counts: [Int] = []

            let sut = AnalyticsEventsModel(log: log) { counts.append($0) }

            #expect(sut.events.map(\.name) == ["opened", "launched"])
            #expect(sut.unseenCount == 2)
            #expect(counts == [2])
        }

        @Test("An event recorded on another thread shows in the model on the main actor, with no reload asked for")
        func liveUpdate() async {
            let log = AnalyticsEventLog(capacity: 10)
            let sut = AnalyticsEventsModel(log: log)
            let updates = sut.$events.values

            await Task.detached {
                log.record(name: "signed_up", properties: ["plan": "pro"], source: nil)
            }.value
            var actual: [String] = []
            for await events in updates where !events.isEmpty {
                actual = events.map(\.name)
                break
            }

            #expect(actual == ["signed_up"])
        }

        @Test("Events that arrive while the list is off screen count as unseen; on screen they are seen at once")
        func unseen() {
            let log = AnalyticsEventLog(capacity: 10)
            var counts: [Int] = []
            let sut = AnalyticsEventsModel(log: log) { counts.append($0) }
            log.record(name: "a", properties: [:], source: nil)
            log.record(name: "b", properties: [:], source: nil)

            sut.reload()

            #expect(sut.unseenCount == 2)

            sut.setShowing(true)

            #expect(sut.unseenCount == 0)

            log.record(name: "c", properties: [:], source: nil)
            sut.reload()

            #expect(sut.unseenCount == 0)

            sut.setShowing(false)
            log.record(name: "d", properties: [:], source: nil)
            sut.reload()

            #expect(sut.unseenCount == 1)
            #expect(counts == [2, 0, 1])
        }

        @Test("Clear drops every event in the log and the model, and the badge")
        func clear() {
            let log = AnalyticsEventLog(capacity: 10)
            log.record(name: "a", properties: [:], source: nil)
            var counts: [Int] = []
            let sut = AnalyticsEventsModel(log: log) { counts.append($0) }

            sut.clear()

            #expect(sut.events.isEmpty)
            #expect(log.events.isEmpty)
            #expect(sut.unseenCount == 0)
            #expect(counts == [1, 0])
        }

        @Test("An event dropped from a full log is no longer counted unseen")
        func droppedNotCounted() {
            let log = AnalyticsEventLog(capacity: 2)
            let sut = AnalyticsEventsModel(log: log)
            for name in ["a", "b", "c", "d"] {
                log.record(name: name, properties: [:], source: nil)
            }

            sut.reload()

            #expect(sut.events.map(\.name) == ["d", "c"])
            #expect(sut.unseenCount == 2)
        }
    }
#endif
