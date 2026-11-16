#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import SwiftUI
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleIssueTests {
        @Test("Errors and faults carry the error glyph; debug, info and notice lines carry none")
        func levelSeverity() {
            let levels: [LogLine.Level] = [.debug, .info, .notice, .error, .fault]
            let expected: [DebugDrawerIssueGlyph.Severity?] = [nil, nil, nil, .error, .error]

            let actual = levels.map(\.severity)

            #expect(actual == expected)
        }

        @Test("The header summary counts the lines in figures with separators, one line in the singular", arguments: [
            (0, "0 lines"), (1, "1 line"), (1204, "1,204 lines")
        ])
        func headerSummary(lineCount: Int, expected: String) {
            let sut = ConsoleHeaderSummary(lineCount: lineCount)

            let actual = sut.text

            #expect(actual == expected)
        }

        @Test("The plugin declares its header accessory")
        func pluginHasAccessory() {
            let sut = AnyDebugDrawerPlugin(ConsolePlugin())

            let actual = sut.headerAccessory

            #expect(actual != nil)
        }
    }
#endif
