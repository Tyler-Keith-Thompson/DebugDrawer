#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    @Suite
    struct ConsoleReportTests {
        @Test("The report gets console.txt: each line's local time, level badge and text, as Copy All copies them")
        func linesAsCopyAll() throws {
            let morning = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: morning, text: "App launched", source: .stdout, level: .info),
                LogLine(timestamp: morning.addingTimeInterval(0.25), text: "Decoding failed", source: .stderr, level: .error)
            ]
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let expected = """
            \(formatter.string(from: morning)) App launched
            \(formatter.string(from: morning.addingTimeInterval(0.25))) ERR Decoding failed
            """
            var actual = DebugDrawerReport()

            ConsolePlugin.contribute(lines, redaction: .none, to: &actual)

            let file = try #require(actual.files.first)
            #expect(actual.files.count == 1)
            #expect(file.name == "console.txt")
            #expect(file.kind == .text)
            #expect(String(bytes: file.data, encoding: .utf8) == expected)
        }

        @Test("console.txt and console-previous.txt mask a metadata field whose key contains a key pattern, keeping the others")
        func metadataMasked() throws {
            let morning = Date(timeIntervalSince1970: 1_800_000_000)
            let line = LogLine(
                timestamp: morning, text: "Paid", source: .sink, level: .info,
                subsystem: "com.example.shop", category: "checkout", metadata: ["order": "1042", "token": "abc", "authUser": "7"]
            )
            let encoder = JSONEncoder()
            let data = try encoder.encode(ConsoleSessionLine(line))
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: morning, id: UUID()), byteCount: data.count
            )))
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let expected = "\(formatter.string(from: morning)) [com.example.shop/checkout] Paid authUser=[REDACTED] order=1042 token=[REDACTED]"
            var actual = DebugDrawerReport()

            ConsolePlugin.contribute([line], redaction: .standard, to: &actual)
            ConsolePlugin.contribute(previous: ConsoleSessionLog(summary: summary, data: data), redaction: .standard, to: &actual)

            #expect(actual.files.map(\.name) == ["console.txt", "console-previous.txt"])
            #expect(actual.files.map { String(bytes: $0.data, encoding: .utf8) } == [expected, expected])
        }

        @Test("The report masks key=value and key: value pairs in a line's text, and in other fields' values, whose key contains a key pattern")
        func textPairsMasked() throws {
            let morning = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(timestamp: morning, text: "Refreshed token=abc for user=7", source: .stdout, level: .info),
                LogLine(timestamp: morning, text: #"Retrying, Session: 9f2; body {"password": "hunter 2"}"#, source: .oslog, level: .error),
                LogLine(
                    timestamp: morning, text: "GET /feed?page=2&access_token=x1&lang=en", source: .sink, level: .debug,
                    metadata: ["request": "id=5 secret=s"]
                )
            ]
            let encoder = JSONEncoder()
            let data = try Data(lines.map { try encoder.encode(ConsoleSessionLine($0)) }.joined(separator: Data("\n".utf8)))
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: morning, id: UUID()), byteCount: data.count
            )))
            let time = {
                let formatter = DateFormatter()
                formatter.dateFormat = "HH:mm:ss.SSS"
                return formatter.string(from: morning)
            }()
            let expected = """
            \(time) Refreshed token=[REDACTED] for user=7
            \(time) ERR Retrying, Session: [REDACTED]; body {"password": "[REDACTED]"}
            \(time) DBG GET /feed?page=2&access_token=[REDACTED]&lang=en request=id=5 secret=[REDACTED]
            """
            var actual = DebugDrawerReport()

            ConsolePlugin.contribute(lines, redaction: .standard, to: &actual)
            ConsolePlugin.contribute(previous: ConsoleSessionLog(summary: summary, data: data), redaction: .standard, to: &actual)

            #expect(actual.files.map(\.name) == ["console.txt", "console-previous.txt"])
            #expect(actual.files.map { String(bytes: $0.data, encoding: .utf8) } == [expected, expected])
        }

        @Test("With no rules the report holds the lines exactly as logged, text and metadata")
        func noRulesUnchanged() throws {
            let morning = Date(timeIntervalSince1970: 1_800_000_000)
            let lines = [
                LogLine(
                    timestamp: morning, text: #"token=abc {"password": "x"} Session: 1"#, source: .sink, level: .error,
                    subsystem: "com.example.shop", category: "auth", metadata: ["token": "abc", "order": "1042"]
                ),
                LogLine(timestamp: morning, text: "plain", source: .stdout, level: .info)
            ]
            let encoder = JSONEncoder()
            let data = try Data(lines.map { try encoder.encode(ConsoleSessionLine($0)) }.joined(separator: Data("\n".utf8)))
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: morning, id: UUID()), byteCount: data.count
            )))
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm:ss.SSS"
            let time = formatter.string(from: morning)
            // Copy All's format as it was before the rules applied: each line as logged.
            let expected = """
            \(time) ERR [com.example.shop/auth] token=abc {"password": "x"} Session: 1 order=1042 token=abc
            \(time) plain
            """
            var actual = DebugDrawerReport()

            ConsolePlugin.contribute(lines, redaction: .none, to: &actual)
            ConsolePlugin.contribute(previous: ConsoleSessionLog(summary: summary, data: data), redaction: .none, to: &actual)

            #expect(actual.files.map { String(bytes: $0.data, encoding: .utf8) } == [expected, expected])
        }

        @Test("The plugin's report masks its lines by the rules the drawer hands it")
        @MainActor func pluginUsesGivenRules() throws {
            var snapshot = ConsoleSnapshot()
            snapshot.log.lines = [LogLine(timestamp: Date(timeIntervalSince1970: 0), text: "token=abc", source: .stdout, level: .info)]
            let transport = DebugDrawerPluginTransport<ConsoleSnapshot, ConsoleCommand>(
                initial: snapshot, snapshots: AsyncStream { $0.finish() }, send: { _ in }
            )
            let sut = ConsolePlugin(transport: transport)
            var masked = DebugDrawerReport()
            var unmasked = DebugDrawerReport()

            sut.contribute(to: &masked, redaction: .standard)
            sut.contribute(to: &unmasked, redaction: .none)

            let maskedText = try #require(masked.files.first.flatMap { String(bytes: $0.data, encoding: .utf8) })
            let unmaskedText = try #require(unmasked.files.first.flatMap { String(bytes: $0.data, encoding: .utf8) })
            #expect(maskedText.hasSuffix(" token=[REDACTED]"))
            #expect(unmaskedText.hasSuffix(" token=abc"))
        }

        @Test("No lines add nothing to the report")
        func noLines() {
            var actual = DebugDrawerReport()

            ConsolePlugin.contribute([], redaction: .standard, to: &actual)

            #expect(actual.files.isEmpty)
        }

        @Test("The plugin adopts the report protocol")
        @MainActor func adopts() {
            let actual = AnyDebugDrawerPlugin(ConsolePlugin())

            #expect(actual.contributesToReport)
        }
    }
#endif
