#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    @Suite
    struct ConsoleLogLineFieldsTests {
        @Test("An os_log entry becomes a line with its subsystem and category as fields, and its message alone as the text")
        func osLogFields() {
            let date = Date(timeIntervalSince1970: 1_800_000_000)

            let actual = ConsoleLogDriver.line(level: .error, subsystem: "com.example.feed", category: "networking", date: date, message: "Timed out")

            #expect(actual.subsystem == "com.example.feed")
            #expect(actual.category == "networking")
            #expect(actual.text == "Timed out")
            #expect(actual.source == .oslog)
            #expect(actual.level == .error)
            #expect(actual.timestamp == date)
        }

        @Test("A stdout or stderr line has an empty subsystem and category")
        func streamsHaveNone() {
            let actual = LogLine(timestamp: Date(timeIntervalSince1970: 0), text: "printed", source: .stdout, level: .info)

            #expect(actual.subsystem.isEmpty)
            #expect(actual.category.isEmpty)
        }

        @Test("A session line keeps the subsystem and category, and reads them back")
        func sessionRoundTrip() throws {
            let line = LogLine(
                timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: "Timed out", source: .oslog, level: .error,
                subsystem: "com.example.feed", category: "networking"
            )
            let data = try JSONEncoder().encode(ConsoleSessionLine(line))

            let actual = try #require(try JSONDecoder().decode(ConsoleSessionLine.self, from: data).logLine)

            #expect(actual.subsystem == "com.example.feed")
            #expect(actual.category == "networking")
            #expect(actual.text == "Timed out")
        }

        @Test("A session line without a subsystem or category leaves both keys out, as format 1 had it")
        func emptyFieldsLeftOut() throws {
            let line = LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: "printed", source: .stdout, level: .info)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let expected = #"{"level":"info","source":"stdout","text":"printed","time":"2027-01-15T08:00:00.000Z"}"#

            let actual = try String(bytes: encoder.encode(ConsoleSessionLine(line)), encoding: .utf8)

            #expect(actual == expected)
        }

        @Test("A format 1 line written before subsystems and categories were kept reads with both empty")
        func formatOneLineReads() throws {
            let data = Data(#"{"level":"info","source":"oslog","text":"[com.example.feed/net] Feed loaded","time":"2027-01-15T08:00:01.000Z"}"#.utf8)

            let actual = try #require(try JSONDecoder().decode(ConsoleSessionLine.self, from: data).logLine)

            #expect(actual.subsystem.isEmpty)
            #expect(actual.category.isEmpty)
            #expect(actual.text == "[com.example.feed/net] Feed loaded")
        }

        @Test("An earlier session's lines filter by subsystem and category like the captured ones")
        func previousSessionFilters() throws {
            let header = #"{"debugDrawerConsoleSession":1,"started":"2027-01-15T08:00:00.000Z","app":"Shop","appVersion":""}"#
            let rows = [
                #"{"category":"net","level":"info","source":"oslog","subsystem":"com.example.feed","text":"a","time":"2027-01-15T08:00:01.000Z"}"#,
                #"{"category":"ui","level":"info","source":"oslog","subsystem":"com.example.feed","text":"b","time":"2027-01-15T08:00:02.000Z"}"#,
                #"{"level":"info","source":"oslog","text":"c","time":"2027-01-15T08:00:03.000Z"}"#
            ]
            let data = Data(([header] + rows).joined(separator: "\n").utf8)
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: data.count
            )))
            let log = ConsoleSessionLog(summary: summary, data: data)
            var sut = ConsoleFilter()
            sut.mutes = [.category("net", subsystem: "com.example.feed")]
            let expected = ["b", "c"]

            let actual = sut.apply(to: log.lines).map(\.text)

            #expect(log.skippedLines == 0)
            #expect(actual == expected)
        }

        @Test("Copy All names the subsystem and category in full before the text")
        func copiedText() {
            let time = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: time, text: "Timed out", source: .oslog, level: .error, subsystem: "com.example.feed", category: "networking"),
                LogLine(timestamp: time, text: "printed", source: .stdout, level: .info)
            ]

            let actual = lines.copiedText(redactedBy: .none).split(separator: "\n").map { $0.split(separator: " ", maxSplits: 1)[1] }

            #expect(actual == ["ERR [com.example.feed/networking] Timed out", "printed"])
        }
    }
#endif
