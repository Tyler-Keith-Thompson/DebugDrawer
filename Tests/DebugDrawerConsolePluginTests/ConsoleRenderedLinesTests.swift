#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    @Suite
    struct ConsoleRenderedLinesTests {
        @Test("Nothing drawn and nothing to draw needs nothing; lines to draw into an empty text redraw it")
        func empty() {
            let line = LogLine(timestamp: Date(timeIntervalSince1970: 0), text: "a", source: .stdout, level: .info)
            let sut = ConsoleRenderedLines()

            #expect(sut.update(to: []) == .none)
            #expect(sut.update(to: [line]) == .redraw)
        }

        @Test("New lines after the drawn ones append, and the same lines need nothing")
        func append() {
            let lines = (0 ..< 3).map { LogLine(timestamp: Date(timeIntervalSince1970: Double($0)), text: "\($0)", source: .stdout, level: .info) }
            var sut = ConsoleRenderedLines()
            sut.redrew(Array(lines[..<2]), starts: [0, 2])

            #expect(sut.update(to: lines) == .extend(dropping: 0, appending: 2))
            #expect(sut.update(to: Array(lines[..<2])) == .none)
        }

        @Test("At capacity, the oldest lines leaving the start drop and the new ones append")
        func capacity() {
            let lines = (0 ..< 5).map { LogLine(timestamp: Date(timeIntervalSince1970: Double($0)), text: "\($0)", source: .stdout, level: .info) }
            var sut = ConsoleRenderedLines()
            sut.redrew(Array(lines[..<3]), starts: [0, 2, 4])

            let actual = sut.update(to: Array(lines[2...]))

            #expect(actual == .extend(dropping: 2, appending: 1))
            #expect(sut.length(ofFirst: 2) == 4)
        }

        @Test("A list of the same length with other lines, as a mute changing at capacity leaves, redraws")
        func sameLengthOtherLines() {
            let lines = (0 ..< 3).map { LogLine(timestamp: Date(timeIntervalSince1970: Double($0)), text: "\($0)", source: .stdout, level: .info) }
            var sut = ConsoleRenderedLines()
            sut.redrew([lines[0], lines[1]], starts: [0, 2])

            let actual = sut.update(to: [lines[0], lines[2]])

            #expect(actual == .redraw)
        }

        @Test("A filter that drops a line from the middle redraws rather than appending past it")
        func filterChange() {
            let lines = (0 ..< 4).map { LogLine(timestamp: Date(timeIntervalSince1970: Double($0)), text: "\($0)", source: .stdout, level: .info) }
            var sut = ConsoleRenderedLines()
            sut.redrew(Array(lines[..<3]), starts: [0, 2, 4])

            let actual = sut.update(to: [lines[0], lines[2], lines[3]])

            #expect(actual == .redraw)
            #expect(sut.update(to: []) == .redraw)
        }

        @Test("Dropping lines shifts the starts of the rest, and appended ones follow")
        func extended() {
            let lines = (0 ..< 4).map { LogLine(timestamp: Date(timeIntervalSince1970: Double($0)), text: "\($0)", source: .stdout, level: .info) }
            var sut = ConsoleRenderedLines()
            sut.redrew(Array(lines[..<3]), starts: [0, 2, 4])

            sut.extended(dropping: 1, appended: [lines[3]], appendedStarts: [4])

            #expect(sut.lines.map(\.text) == ["1", "2", "3"])
            #expect(sut.starts == [0, 2, 4])
        }

        @Test("The line at an offset is the last starting at or before it; the newline after a line is that line's")
        func lineAtOffset() {
            let lines = (0 ..< 3).map { LogLine(timestamp: Date(timeIntervalSince1970: Double($0)), text: "\($0)", source: .stdout, level: .info) }
            var sut = ConsoleRenderedLines()
            sut.redrew(lines, starts: [0, 10, 20])

            #expect(sut.line(at: 0)?.text == "0")
            #expect(sut.line(at: 9)?.text == "0")
            #expect(sut.line(at: 10)?.text == "1")
            #expect(sut.line(at: 25)?.text == "2")
            #expect(ConsoleRenderedLines().line(at: 0) == nil)
        }
    }
#endif
