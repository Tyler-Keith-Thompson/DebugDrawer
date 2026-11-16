#if DEBUG
    @testable import DebugDrawerCrashReportsPlugin
    import Testing

    struct StackFrameTests {
        @Test("A backtrace_symbols line reads as its index, image and symbol, without the offset")
        func backtraceSymbols() {
            let line = "1   Example              0x0000000100004a1c $s7Example11ContentViewV5crashyyF + 48"
            let expected = StackFrame(index: 1, image: "Example", symbol: "$s7Example11ContentViewV5crashyyF")

            let actual = StackFrame(line: line, position: 0)

            #expect(actual == expected)
        }

        @Test("A MetricKit line, which names no symbol, keeps its address and offset as the symbol")
        func metricKit() {
            let line = "2 Example 0x100004000 + 16384"
            let expected = StackFrame(index: 2, image: "Example", symbol: "0x100004000 + 16384")

            let actual = StackFrame(line: line, position: 0)

            #expect(actual == expected)
        }

        @Test("A line with no address keeps its address alone, and a line in neither form is its own symbol at its position")
        func edges() {
            let bare = "0 dyld 0x1"
            let unreadable = "2 dyld ?"
            let expected = [
                StackFrame(index: 0, image: "dyld", symbol: "0x1"),
                StackFrame(index: 5, image: "???", symbol: "2 dyld ?")
            ]

            let actual = [StackFrame(line: bare, position: 0), StackFrame(line: unreadable, position: 5)]

            #expect(actual == expected)
        }

        @Test("Only frames in the app's executable are its own code")
        func ownCode() {
            let frames = StackFrame.frames(["0 Example 0x1 main + 4", "1 libdyld.dylib 0x2 start + 8"])
            let expected = [true, false]

            let actual = frames.map { $0.isOwnCode("Example") }

            #expect(actual == expected)
        }
    }
#endif
