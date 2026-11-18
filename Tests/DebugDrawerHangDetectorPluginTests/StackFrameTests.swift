#if DEBUG
    @testable import DebugDrawerHangDetectorPlugin
    import Foundation
    import Testing

    struct StackFrameTests {
        @Test("A Symbolicator line reads as its index, image and symbol, without the offset")
        func symbolicatorLine() {
            let line = "1 Example 0x0000000100004a1c $s7Example11ContentViewV5stallyyF + 48"
            let expected = StackFrame(index: 1, image: "Example", symbol: "$s7Example11ContentViewV5stallyyF")

            let actual = StackFrame(line: line, position: 0)

            #expect(actual == expected)
        }

        @Test("An Objective-C frame keeps the spaces in its instance or class method's symbol")
        func objectiveCFrames() {
            let lines = [
                "3 CoreFoundation 0x00000001804b8c40 -[NSObject(NSObject) doesNotRecognizeSelector:] + 136",
                "4 CoreFoundation 0x00000001804b9d0c +[NSException raise:format:arguments:] + 96"
            ]
            let expected = [
                StackFrame(index: 3, image: "CoreFoundation", symbol: "-[NSObject(NSObject) doesNotRecognizeSelector:]"),
                StackFrame(index: 4, image: "CoreFoundation", symbol: "+[NSException raise:format:arguments:]")
            ]

            let actual = StackFrame.frames(lines)

            #expect(actual == expected)
        }

        @Test("An image whose name has spaces reads whole, with or without a symbol")
        func imageWithSpaces() {
            let lines = [
                "1 My Example App 0x0000000100004a1c $s14MyExampleApp4mainyyF + 12",
                "2 My Example App 0x0000000100004b00",
                "3 My Example App 0x100004000 + 16384"
            ]
            let expected = [
                StackFrame(index: 1, image: "My Example App", symbol: "$s14MyExampleApp4mainyyF"),
                StackFrame(index: 2, image: "My Example App", symbol: "0x0000000100004b00"),
                StackFrame(index: 3, image: "My Example App", symbol: "0x100004000 + 16384")
            ]

            let actual = StackFrame.frames(lines)

            #expect(actual == expected)
        }

        @Test("A C frame reads as its image and function, without the offset")
        func cFrame() {
            let line = "0 libsystem_kernel.dylib 0x00000001802a1a6c __semwait_signal + 8"
            let expected = StackFrame(index: 0, image: "libsystem_kernel.dylib", symbol: "__semwait_signal")

            let actual = StackFrame(line: line, position: 3)

            #expect(actual == expected)
        }

        @Test("A frame dladdr finds no symbol or no image for keeps its address as the symbol")
        func framesWithoutSymbol() {
            let lines = [
                "5 Example 0x0000000104a1c3d8",
                "6 ??? 0x0000000000000010"
            ]
            let expected = [
                StackFrame(index: 5, image: "Example", symbol: "0x0000000104a1c3d8"),
                StackFrame(index: 6, image: "???", symbol: "0x0000000000000010")
            ]

            let actual = StackFrame.frames(lines)

            #expect(actual == expected)
        }

        @Test("Lines the Symbolicator writes for this thread read in order, none left whole or with an offset in its symbol")
        func realStack() {
            let addresses = Thread.callStackReturnAddresses.map(\.uintValue)
            let lines = Symbolicator.lines(for: addresses)
            let expected = Array(0..<addresses.count)

            let actual = StackFrame.frames(lines)

            let unread = actual.filter { $0.symbol.contains(" + ") || $0.symbol == lines[$0.index] }
            #expect(actual.map(\.index) == expected)
            #expect(unread.isEmpty)
        }

        @Test("A MetricKit line, which names no symbol, keeps its address and offset as the symbol")
        func metricKit() {
            let line = "2 Example 0x100004000 + 16384"
            let expected = StackFrame(index: 2, image: "Example", symbol: "0x100004000 + 16384")

            let actual = StackFrame(line: line, position: 0)

            #expect(actual == expected)
        }

        @Test("A line in neither form, such as a MetricKit frame with no address, is its own symbol at its position")
        func unreadable() {
            let lines = ["0 Example ? + 16384", "2 dyld ?"]
            let expected = [
                StackFrame(index: 4, image: "???", symbol: "0 Example ? + 16384"),
                StackFrame(index: 5, image: "???", symbol: "2 dyld ?")
            ]

            let actual = [StackFrame(line: lines[0], position: 4), StackFrame(line: lines[1], position: 5)]

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
