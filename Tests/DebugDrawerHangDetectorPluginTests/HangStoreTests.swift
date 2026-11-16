#if DEBUG
    @testable import DebugDrawerHangDetectorPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct HangStoreTests {
        @Test("A hang is kept unseen, and the badge counts it")
        func add() {
            var counts: [Int] = []
            let sut = HangStore(threshold: .milliseconds(250)) { _ in } onUnseenCountChange: { counts.append($0) }
            let event = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(612), frames: ["0 Example 0x1"],
                source: .detected, isSeen: false
            )

            sut.add(event)

            #expect(sut.events == [event])
            #expect(sut.unseenCount == 1)
            #expect(counts == [1])
        }

        @Test("Hangs are listed newest first, and only the newest fifty are kept")
        func keepsNewest() {
            let sut = HangStore(threshold: .milliseconds(250))
            let events = (0 ..< 52).map { second in
                HangEvent(
                    id: UUID(), date: Date(timeIntervalSince1970: TimeInterval(second)), duration: .milliseconds(300), frames: [],
                    source: .detected, isSeen: false
                )
            }
            let expected = Array(events.reversed().prefix(50))

            for event in events.shuffled() {
                sut.add(event)
            }

            #expect(sut.events == expected)
        }

        @Test("Opening a hang marks it seen, which lowers the badge")
        func markSeen() {
            var counts: [Int] = []
            let sut = HangStore(threshold: .milliseconds(250)) { _ in } onUnseenCountChange: { counts.append($0) }
            let first = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 2), duration: .milliseconds(300), frames: [], source: .detected, isSeen: false
            )
            let second = HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(400), frames: [], source: .detected, isSeen: false
            )
            sut.add(first)
            sut.add(second)

            sut.markSeen(first.id)

            #expect(sut.events.map(\.isSeen) == [true, false])
            #expect(counts == [1, 2, 1])
        }

        @Test("Mark All Seen clears the badge and keeps the hangs")
        func markAllSeen() {
            var counts: [Int] = []
            let sut = HangStore(threshold: .milliseconds(250)) { _ in } onUnseenCountChange: { counts.append($0) }
            sut.add(HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(300), frames: [], source: .detected, isSeen: false
            ))

            sut.markAllSeen()

            #expect(sut.events.count == 1)
            #expect(sut.unseenCount == 0)
            #expect(counts == [1, 0])
        }

        @Test("Clear All forgets every hang and clears the badge")
        func clear() {
            var counts: [Int] = []
            let sut = HangStore(threshold: .milliseconds(250)) { _ in } onUnseenCountChange: { counts.append($0) }
            sut.add(HangEvent(
                id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(300), frames: [], source: .detected, isSeen: false
            ))

            sut.clear()

            #expect(sut.events.isEmpty)
            #expect(counts == [1, 0])
        }

        @Test("Changing the threshold tells the monitor")
        func threshold() {
            var thresholds: [Duration] = []
            let sut = HangStore(threshold: .milliseconds(250)) { thresholds.append($0) }

            sut.threshold = .milliseconds(1000)

            #expect(sut.threshold == .milliseconds(1000))
            #expect(thresholds == [.milliseconds(1000)])
        }

        @Test("MetricKit's hang diagnostics are kept; one that isn't a diagnostic is dropped")
        func receive() {
            let sut = HangStore(threshold: .milliseconds(250))
            let json = #"{"callStackTree": {"callStacks": [{"callStackRootFrames": [{"binaryName": "Example", "address": 4096}]}]}}"#
            let date = Date(timeIntervalSince1970: 1_763_290_000)

            sut.receive([
                HangDiagnostic(json: Data(json.utf8), duration: .seconds(2), date: date),
                HangDiagnostic(json: Data("garbage".utf8), duration: .seconds(1), date: date)
            ])

            #expect(sut.events.map(\.duration) == [.seconds(2)])
            #expect(sut.events.map(\.source) == [.metricKit])
            #expect(sut.unseenCount == 1)
        }
    }
#endif
