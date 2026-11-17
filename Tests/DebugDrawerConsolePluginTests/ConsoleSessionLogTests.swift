#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    @Suite
    struct ConsoleSessionLogTests {
        @Test("A file with no header, as one deleted and started again mid-session, still reads its lines")
        func noHeader() throws {
            let data = Data(#"{"level":"info","source":"oslog","text":"Feed loaded","time":"2027-01-15T08:00:01.000Z"}"#.utf8) + Data("\n".utf8)
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: data.count
            )))

            let actual = ConsoleSessionLog(summary: summary, data: data)

            #expect(actual.header == nil)
            #expect(actual.lines.map(\.text) == ["Feed loaded"])
            #expect(actual.lines.map(\.timestamp) == [Date(timeIntervalSince1970: 1_800_000_001)])
            #expect(actual.skippedLines == 0)
        }

        @Test("A file whose header names a later format reads as empty, its lines counted unreadable")
        func laterFormat() throws {
            let header = Data(#"{"debugDrawerConsoleSession":2,"started":"2027-01-15T08:00:00.000Z","app":"Shop","appVersion":""}"#.utf8)
            let data = header + Data("\n".utf8) + Data(#"{"something":"new"}"#.utf8) + Data("\n".utf8)
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: data.count
            )))

            let actual = ConsoleSessionLog(summary: summary, data: data)

            #expect(actual.header?.format == 2)
            #expect(actual.lines.isEmpty)
            #expect(actual.skippedLines == 1)
        }

        @Test("A line whose level or source this build doesn't know is skipped and counted, and the lines around it are read")
        func unknownLevel() throws {
            let rows = [
                #"{"level":"info","source":"oslog","text":"before","time":"2027-01-15T08:00:01.000Z"}"#,
                #"{"level":"trace","source":"oslog","text":"new level","time":"2027-01-15T08:00:02.000Z"}"#,
                #"{"level":"info","source":"socket","text":"new source","time":"2027-01-15T08:00:03.000Z"}"#,
                #"{"level":"error","source":"stderr","text":"after","time":"2027-01-15T08:00:04.000Z"}"#
            ]
            let data = Data(rows.joined(separator: "\n").utf8)
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: data.count
            )))

            let actual = ConsoleSessionLog(summary: summary, data: data)

            #expect(actual.lines.map(\.text) == ["before", "after"])
            #expect(actual.lines.map(\.level) == [.info, .error])
            #expect(actual.skippedLines == 2)
        }

        @Test("Every level and source reads back as it was written")
        func roundTrip() throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let expected = [
                LogLine(timestamp: started.addingTimeInterval(0.125), text: "line 0", source: .stdout, level: .debug),
                LogLine(timestamp: started.addingTimeInterval(1.125), text: "line 1", source: .stderr, level: .info),
                LogLine(timestamp: started.addingTimeInterval(2.125), text: "line 2", source: .oslog, level: .notice),
                LogLine(timestamp: started.addingTimeInterval(3.125), text: "line 3", source: .oslog, level: .error),
                LogLine(timestamp: started.addingTimeInterval(4.125), text: "line 4", source: .stdout, level: .fault)
            ]
            let encoder = JSONEncoder()
            let rows = try expected.map { try encoder.encode(ConsoleSessionLine($0)) }
            let data = Data(rows.joined(separator: Data("\n".utf8)))
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started, id: UUID()), byteCount: data.count
            )))

            let actual = ConsoleSessionLog(summary: summary, data: data).lines

            #expect(actual.map(\.level) == expected.map(\.level))
            #expect(actual.map(\.source) == expected.map(\.source))
            #expect(actual.map(\.text) == expected.map(\.text))
            #expect(actual.map(\.timestamp) == expected.map(\.timestamp))
        }

        @Test("A session's name starts with its start, so names sort as sessions started, and reads back to it")
        func names() throws {
            let earlier = Date(timeIntervalSince1970: 1_800_000_000.25)
            let later = Date(timeIntervalSince1970: 1_800_000_060)
            let earlierName = ConsoleSessionSummary.name(started: earlier, id: UUID())
            let laterName = ConsoleSessionSummary.name(started: later, id: UUID())

            let actual = try #require(ConsoleSessionSummary(ConsoleSessionFile(name: earlierName, byteCount: 10)))

            #expect(earlierName.hasPrefix("2027-01-15T080000.250Z-"))
            #expect(earlierName.hasSuffix(".jsonl"))
            #expect(earlierName < laterName)
            #expect(actual.started == earlier)
            #expect(ConsoleSessionSummary(ConsoleSessionFile(name: "notes.jsonl", byteCount: 10)) == nil)
            #expect(ConsoleSessionSummary(ConsoleSessionFile(name: "2027-01-15T080000.250Z-x.txt", byteCount: 10)) == nil)
        }

        @Test("The report gets the newest earlier session as console-previous.txt, every level, as Copy All copies them; none adds nothing")
        func report() throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: started.addingTimeInterval(1), text: "Fetching feed", source: .oslog, level: .debug),
                LogLine(timestamp: started.addingTimeInterval(2), text: "Decoding failed", source: .stderr, level: .error)
            ]
            let encoder = JSONEncoder()
            let data = try Data(lines.map { try encoder.encode(ConsoleSessionLine($0)) }.joined(separator: Data("\n".utf8)))
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started, id: UUID()), byteCount: data.count
            )))
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let expected = """
            \(formatter.string(from: started.addingTimeInterval(1))) DBG Fetching feed
            \(formatter.string(from: started.addingTimeInterval(2))) ERR Decoding failed
            """
            var report = DebugDrawerReport()
            var empty = DebugDrawerReport()

            ConsolePlugin.contribute(previous: ConsoleSessionLog(summary: summary, data: data), to: &report)
            ConsolePlugin.contribute(previous: nil, to: &empty)

            let file = try #require(report.files.first)
            #expect(report.files.count == 1)
            #expect(file.name == "console-previous.txt")
            #expect(file.kind == .text)
            #expect(String(bytes: file.data, encoding: .utf8) == expected)
            #expect(empty.files.isEmpty)
        }
    }
#endif
