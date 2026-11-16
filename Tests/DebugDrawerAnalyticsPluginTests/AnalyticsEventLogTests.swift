#if DEBUG
    @testable import DebugDrawerAnalyticsPlugin
    import Foundation
    import os
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct AnalyticsEventLogTests {
        @Test("A recorded event is kept with its name, properties, source and the time of the call")
        func record() throws {
            let expectedTime = Date(timeIntervalSince1970: 1_763_290_000)
            let sut = AnalyticsEventLog(capacity: 10) { expectedTime }
            let expectedProperties: [String: AnalyticsValue] = ["plan": "pro", "seats": 3]

            sut.record(name: "checkout_completed", properties: expectedProperties, source: "Segment")

            let actual = try #require(sut.events.first)
            #expect(sut.events.count == 1)
            #expect(actual.id == 1)
            #expect(actual.name == "checkout_completed")
            #expect(actual.properties == expectedProperties)
            #expect(actual.source == "Segment")
            #expect(actual.timestamp == expectedTime)
        }

        @Test("Events are listed newest first, each with the next identity")
        func newestFirst() {
            let sut = AnalyticsEventLog(capacity: 10)
            let expectedNames = ["third", "second", "first"]
            let expectedIDs = [3, 2, 1]

            sut.record(name: "first", properties: [:], source: nil)
            sut.record(name: "second", properties: [:], source: nil)
            sut.record(name: "third", properties: [:], source: nil)

            #expect(sut.events.map(\.name) == expectedNames)
            #expect(sut.events.map(\.id) == expectedIDs)
        }

        @Test("A new log is empty")
        func empty() {
            let sut = AnalyticsEventLog(capacity: 10)

            #expect(sut.events.isEmpty)
            #expect(sut.capacity == 10)
        }

        @Test("An empty source is none")
        func emptySource() throws {
            let sut = AnalyticsEventLog(capacity: 10)

            sut.record(name: "opened", properties: [:], source: "")

            #expect(try #require(sut.events.first).source == nil)
        }

        @Test("A full log drops the oldest event for each new one, keeping exactly its capacity",
              arguments: [1, 2, 3, 7])
        func ringBound(capacity: Int) {
            let sut = AnalyticsEventLog(capacity: capacity)
            let recorded = 10
            let expectedNames = (recorded - capacity ..< recorded).reversed().map { "event \($0)" }

            for index in 0 ..< recorded {
                sut.record(name: "event \(index)", properties: [:], source: nil)
            }

            #expect(sut.events.map(\.name) == expectedNames)
        }

        @Test("For every capacity up to 6, count up to 20 and resize between, the log keeps what the newest of a plain array keeps")
        func ringMatchesNaiveReference() {
            for capacity in 1 ... 6 {
                for count in 0 ... 20 {
                    for resized in 1 ... 6 {
                        let sut = AnalyticsEventLog(capacity: capacity)
                        var reference: [String] = []
                        var referenceCapacity = capacity
                        for index in 0 ..< count {
                            if index == count / 2 {
                                sut.resize(to: resized)
                                referenceCapacity = resized
                                reference = Array(reference.suffix(resized))
                            }
                            sut.record(name: "\(index)", properties: [:], source: nil)
                            reference = Array((reference + ["\(index)"]).suffix(referenceCapacity))
                        }

                        #expect(sut.events.map(\.name) == reference.reversed(), "capacity \(capacity), count \(count), resized to \(resized)")
                    }
                }
            }
        }

        @Test("A log filled exactly to its capacity drops nothing")
        func ringExactlyFull() {
            let sut = AnalyticsEventLog(capacity: 3)
            let expectedNames = ["c", "b", "a"]

            for name in ["a", "b", "c"] {
                sut.record(name: name, properties: [:], source: nil)
            }

            #expect(sut.events.map(\.name) == expectedNames)
        }

        @Test("Shrinking keeps the newest events; growing keeps them all and takes more")
        func resize() {
            let sut = AnalyticsEventLog(capacity: 4)
            for name in ["a", "b", "c", "d", "e"] {
                sut.record(name: name, properties: [:], source: nil)
            }

            sut.resize(to: 2)

            #expect(sut.events.map(\.name) == ["e", "d"])

            sut.resize(to: 3)
            sut.record(name: "f", properties: [:], source: nil)
            sut.record(name: "g", properties: [:], source: nil)

            #expect(sut.events.map(\.name) == ["g", "f", "e"])
            #expect(sut.capacity == 3)
        }

        @Test("Removing every event empties the log, and identities keep counting")
        func clear() throws {
            let sut = AnalyticsEventLog(capacity: 2)
            for name in ["a", "b", "c"] {
                sut.record(name: name, properties: [:], source: nil)
            }

            sut.removeAll()

            #expect(sut.events.isEmpty)

            sut.record(name: "d", properties: [:], source: nil)

            #expect(sut.events.map(\.name) == ["d"])
            #expect(try #require(sut.events.first).id == 4)
        }

        @Test("Events recorded from many tasks at once are each kept once")
        func concurrentRecord() async {
            let sut = AnalyticsEventLog(capacity: 10000)
            let tasks = 50
            let eventsPerTask = 100
            let expectedCount = tasks * eventsPerTask

            await withTaskGroup(of: Void.self) { group in
                for task in 0 ..< tasks {
                    group.addTask {
                        for index in 0 ..< eventsPerTask {
                            sut.record(name: "task \(task) event \(index)", properties: ["index": .int(index)], source: nil)
                        }
                    }
                }
            }

            let actual = sut.events
            #expect(actual.count == expectedCount)
            #expect(Set(actual.map(\.name)).count == expectedCount)
            #expect(actual.map(\.id) == Array((1 ... expectedCount).reversed()))
        }

        @Test("Events recorded from many tasks into a full log keep exactly its capacity, the newest")
        func concurrentRecordIntoFullLog() async {
            let sut = AnalyticsEventLog(capacity: 100)
            let expectedIDs = Array((4901 ... 5000).reversed())

            await withTaskGroup(of: Void.self) { group in
                for task in 0 ..< 50 {
                    group.addTask {
                        for index in 0 ..< 100 {
                            sut.record(name: "task \(task) event \(index)", properties: [:], source: nil)
                        }
                    }
                }
            }

            #expect(sut.events.map(\.id) == expectedIDs)
        }

        @Test("A burst of changes reports one until the events are read, then the next one again")
        func changeCoalescing() {
            let sut = AnalyticsEventLog(capacity: 10)
            let reports = OSAllocatedUnfairLock(initialState: 0)
            sut.observe { reports.withLock { $0 += 1 } }

            sut.record(name: "a", properties: [:], source: nil)
            sut.record(name: "b", properties: [:], source: nil)
            sut.removeAll()

            #expect(reports.withLock(\.self) == 1)

            _ = sut.events
            sut.record(name: "c", properties: [:], source: nil)

            #expect(reports.withLock(\.self) == 2)
        }

        @Test("Shrinking reports a change only when it drops an event")
        func resizeReports() {
            let sut = AnalyticsEventLog(capacity: 10)
            sut.record(name: "a", properties: [:], source: nil)
            sut.record(name: "b", properties: [:], source: nil)
            let reports = OSAllocatedUnfairLock(initialState: 0)
            sut.observe { reports.withLock { $0 += 1 } }

            sut.resize(to: 5)

            #expect(reports.withLock(\.self) == 0)

            sut.resize(to: 1)

            #expect(reports.withLock(\.self) == 1)
        }
    }
#endif
