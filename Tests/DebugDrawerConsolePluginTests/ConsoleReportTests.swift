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

            ConsolePlugin.contribute(lines, to: &actual)

            let file = try #require(actual.files.first)
            #expect(actual.files.count == 1)
            #expect(file.name == "console.txt")
            #expect(file.kind == .text)
            #expect(String(bytes: file.data, encoding: .utf8) == expected)
        }

        @Test("No lines add nothing to the report")
        func noLines() {
            var actual = DebugDrawerReport()

            ConsolePlugin.contribute([], to: &actual)

            #expect(actual.files.isEmpty)
        }

        @Test("The plugin adopts the report protocol")
        @MainActor func adopts() {
            let actual = AnyDebugDrawerPlugin(ConsolePlugin())

            #expect(actual.contributesToReport)
        }
    }
#endif
