#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    @Suite
    struct ConsoleLineAssemblerTests {
        @Test("A read that ends inside a 4-byte emoji keeps its first bytes until the rest arrive, and the line shows it whole")
        func splitInsideEmoji() throws {
            let bytes = Data("Rocket 🚀 launched\n".utf8)
            let cut = try #require(bytes.firstIndex(of: 0xF0)) + 2
            var sut = ConsoleLineAssembler()
            let expected = ["Rocket 🚀 launched"]

            let first = sut.lines(in: bytes[..<cut])
            let actual = sut.lines(in: bytes[cut...])

            #expect(first.isEmpty)
            #expect(actual == expected)
        }

        @Test("A read that ends inside a 2-byte é keeps its first byte until the second arrives")
        func splitInsideTwoByteCharacter() throws {
            let bytes = Data("Café opened\n".utf8)
            let cut = try #require(bytes.firstIndex(of: 0xC3)) + 1
            var sut = ConsoleLineAssembler()
            let expected = ["Café opened"]

            let first = sut.lines(in: bytes[..<cut])
            let actual = sut.lines(in: bytes[cut...])

            #expect(first.isEmpty)
            #expect(actual == expected)
        }

        @Test("A line split across three reads is one line, shown when its newline arrives")
        func lineAcrossThreeReads() {
            var sut = ConsoleLineAssembler()
            let expected = ["Loading feed... done"]

            let first = sut.lines(in: Data("Loading ".utf8))
            let second = sut.lines(in: Data("feed...".utf8))
            let actual = sut.lines(in: Data(" done\n".utf8))

            #expect(first.isEmpty)
            #expect(second.isEmpty)
            #expect(actual == expected)
        }

        @Test("A carriage return before a newline is dropped, also when the read ends between them")
        func crlf() {
            var sut = ConsoleLineAssembler()
            let expected = ["first", "second", "third"]

            let whole = sut.lines(in: Data("first\r\nsecond\r".utf8))
            let rest = sut.lines(in: Data("\nthird\r\n".utf8))
            let actual = whole + rest

            #expect(actual == expected)
        }

        @Test("An empty read completes nothing and loses nothing waiting")
        func emptyRead() {
            var sut = ConsoleLineAssembler()
            let expected = ["half and half"]

            let first = sut.lines(in: Data("half ".utf8))
            let empty = sut.lines(in: Data())
            let actual = sut.lines(in: Data("and half\n".utf8))

            #expect(first.isEmpty)
            #expect(empty.isEmpty)
            #expect(actual == expected)
        }

        @Test("Many lines in one read come out in order, empty lines included")
        func manyLinesInOneRead() {
            let expected = (0 ..< 100).map { $0 % 10 == 0 ? "" : "line \($0)" }
            let bytes = Data(expected.map { "\($0)\n" }.joined().utf8)
            var sut = ConsoleLineAssembler()

            let actual = sut.lines(in: bytes)

            #expect(actual == expected)
            #expect(sut.flush() == nil)
        }

        @Test("At the end of the stream, a last line without a newline is flushed once; with nothing waiting there is none")
        func flushTrailingLine() {
            var sut = ConsoleLineAssembler()
            _ = sut.lines(in: Data("done\nno newline".utf8))
            let expected = "no newline"

            let actual = sut.flush()

            #expect(actual == expected)
            #expect(sut.flush() == nil)
        }

        @Test("Bytes that aren't UTF-8 show as replacement characters, and the line and those around it stay")
        func invalidUTF8() {
            var sut = ConsoleLineAssembler()
            let bytes = Data("before\nbad ".utf8) + Data([0xFF, 0xFE]) + Data(" bytes\nafter\n".utf8)
            let expected = ["before", "bad \u{FFFD}\u{FFFD} bytes", "after"]

            let actual = sut.lines(in: bytes)

            #expect(actual == expected)
        }

        @Test("Bytes waiting past the maximum are cut there, before the start of a character the cut would split")
        func overlongLineCutsAtCharacterBoundary() {
            var sut = ConsoleLineAssembler(maximumLineLength: 8)
            let expected = ["abcdefg", "é🚀hi"]

            // "abcdefg" is 7 bytes and é 2 more, so the 8-byte cut falls inside é and moves
            // before it; é, 🚀, "h" and "i" are the next 8 bytes, and "j" waits.
            let actual = sut.lines(in: Data("abcdefgé🚀hij".utf8))

            #expect(actual == expected)
            #expect(sut.flush() == "j")
        }

        @Test("The smallest maximum, 4 bytes, still holds a 4-byte emoji whole")
        func smallestMaximum() {
            var sut = ConsoleLineAssembler(maximumLineLength: 4)
            let expected = ["a", "🚀"]

            let actual = sut.lines(in: Data("a🚀b".utf8))

            #expect(actual == expected)
            #expect(sut.flush() == "b")
        }

        // Exhaustive rather than random: every way to cut each text into three reads, and into
        // one read per byte, against splitting the whole text on newlines.
        @Test(
            "For every way to cut a text into reads, the lines equal splitting the whole text on newlines",
            arguments: [
                "plain\nlines\n",
                "no trailing newline",
                "\n\nleading and doubled\n\n",
                "Café 🚀 名前\nüber\r\nend",
                "👩‍👩‍👧 family\n\r\n🇨🇦\n"
            ]
        )
        func everyCutMatchesSplittingTheWhole(text: String) {
            func reference(_ text: String) -> [String] {
                let pieces = text.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false).map { scalars in
                    String(scalars.last == "\r" ? scalars.dropLast() : scalars)
                }
                return pieces.last == "" ? Array(pieces.dropLast()) : pieces
            }
            func assemble(_ chunks: [Data]) -> [String] {
                var sut = ConsoleLineAssembler()
                let lines = chunks.flatMap { sut.lines(in: $0) }
                return lines + (sut.flush().map { [$0] } ?? [])
            }
            let bytes = Data(text.utf8)
            let expected = reference(text)
            var mismatches: [String] = []

            for first in 0 ... bytes.count {
                for second in first ... bytes.count {
                    let chunks = [bytes[..<first], bytes[first ..< second], bytes[second...]].map { Data($0) }
                    if assemble(chunks) != expected { mismatches.append("cut at \(first) and \(second)") }
                }
            }
            let bytewise = assemble(bytes.map { Data([$0]) })

            #expect(mismatches.isEmpty)
            #expect(bytewise == expected)
        }
    }
#endif
