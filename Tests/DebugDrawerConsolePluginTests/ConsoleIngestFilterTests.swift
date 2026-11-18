#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    // Captured lines reach `lines` through the store's batching, so each store test waits for the
    // published list to show the last line it sent.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleIngestFilterTests {
        @Test(
            "Apple subsystems' debug and info lines are dropped by default",
            arguments: [LogLine.Level.debug, .info]
        )
        func dropsSystemChatter(level: LogLine.Level) {
            let sut = ConsoleIngestFilter()
            let line = LogLine(
                timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: "Event dispatched", source: .oslog, level: level,
                subsystem: "com.apple.UIKit", category: "EventDispatch"
            )

            let actual = sut.keeps(line)

            #expect(!actual)
        }

        @Test(
            "Apple subsystems' notice, error and fault lines are kept",
            arguments: [LogLine.Level.notice, .error, .fault]
        )
        func keepsSystemProblems(level: LogLine.Level) {
            let sut = ConsoleIngestFilter()
            let line = LogLine(
                timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: "Connection failed", source: .oslog, level: level,
                subsystem: "com.apple.network", category: "connection"
            )

            let actual = sut.keeps(line)

            #expect(actual)
        }

        @Test(
            "Every level of a subsystem that isn't Apple's is kept, even one that only starts like Apple's",
            arguments: [LogLine.Level.debug, .info, .notice, .error, .fault]
        )
        func keepsHostLines(level: LogLine.Level) {
            let sut = ConsoleIngestFilter()
            let subsystems: [String] = ["com.example.shop", "com.applesauce.app", "apple", ""]

            let actual = subsystems.map { subsystem in
                sut.keeps(LogLine(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: "Cart updated", source: .oslog, level: level,
                    subsystem: subsystem
                ))
            }

            #expect(actual == [true, true, true, true])
        }

        @Test(
            "With system debug logs included, Apple subsystems' debug and info lines are kept",
            arguments: [LogLine.Level.debug, .info]
        )
        func includesSystemChatter(level: LogLine.Level) {
            let sut = ConsoleIngestFilter(includesSystemDebugLogs: true)
            let line = LogLine(
                timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: "Event dispatched", source: .oslog, level: level,
                subsystem: "com.apple.UIKit", category: "EventDispatch"
            )

            let actual = sut.keeps(line)

            #expect(actual)
        }

        @Test("2,100 debug lines from com.apple.UIKit evict none of the host's lines")
        func hostLinesSurviveSystemChatter() async {
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
            let expected = ["host 0", "host 1", "host 2", "host 3"]

            for chunk in 0 ..< 3 {
                sut.ingest(LogLine(timestamp: timestamp, text: "host \(chunk)", source: .oslog, level: .debug, subsystem: "com.example.shop"))
                for chatter in 0 ..< 700 {
                    sut.ingest(LogLine(
                        timestamp: timestamp, text: "UIKit \(chatter)", source: .oslog, level: .debug,
                        subsystem: "com.apple.UIKit", category: "EventDispatch"
                    ))
                }
            }
            sut.ingest(LogLine(timestamp: timestamp, text: "host 3", source: .oslog, level: .debug, subsystem: "com.example.shop"))
            for await _ in sut.$lines.first(where: { $0.last?.text == "host 3" }).values {}

            let actual = sut.lines.map(\.text)
            #expect(actual == expected)
            #expect(sut.droppedLineCount == 0)
        }

        @Test("Error and fault lines from Apple subsystems are kept among their debug chatter")
        func systemProblemsSurviveSystemChatter() async {
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
            let expected = ["UIKit error", "network fault", "host done"]

            for chatter in 0 ..< 2100 {
                sut.ingest(LogLine(
                    timestamp: timestamp, text: "UIKit \(chatter)", source: .oslog, level: .debug, subsystem: "com.apple.UIKit"
                ))
            }
            sut.ingest(LogLine(timestamp: timestamp, text: "UIKit error", source: .oslog, level: .error, subsystem: "com.apple.UIKit"))
            sut.ingest(LogLine(timestamp: timestamp, text: "network fault", source: .oslog, level: .fault, subsystem: "com.apple.network"))
            sut.ingest(LogLine(timestamp: timestamp, text: "host done", source: .oslog, level: .info, subsystem: "com.example.shop"))
            for await _ in sut.$lines.first(where: { $0.last?.text == "host done" }).values {}

            let actual = sut.lines.map(\.text)
            #expect(actual == expected)
        }

        @Test("A store that includes system debug logs keeps Apple subsystems' debug lines")
        func storeIncludesSystemChatter() async {
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            sut.ingestFilter.includesSystemDebugLogs = true
            let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
            let expected = ["UIKit 0", "UIKit 1"]

            for text in expected {
                sut.ingest(LogLine(timestamp: timestamp, text: text, source: .oslog, level: .debug, subsystem: "com.apple.UIKit"))
            }
            for await _ in sut.$lines.first(where: { $0.last?.text == "UIKit 1" }).values {}

            let actual = sut.lines.map(\.text)
            #expect(actual == expected)
        }
    }
#endif
