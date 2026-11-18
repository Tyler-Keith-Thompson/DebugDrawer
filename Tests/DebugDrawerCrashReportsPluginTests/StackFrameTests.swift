#if DEBUG
    @testable import DebugDrawerCrashReportsPlugin
    import Darwin
    import Foundation
    import Testing

    struct StackFrameTests {
        @Test("A backtrace_symbols line reads as its index, image and symbol, without the offset")
        func backtraceSymbols() {
            let line = "1   Example              0x0000000100004a1c $s7Example11ContentViewV5crashyyF + 48"
            let expected = StackFrame(index: 1, image: "Example", symbol: "$s7Example11ContentViewV5crashyyF")

            let actual = StackFrame(line: line, position: 0)

            #expect(actual == expected)
        }

        @Test("A padded backtrace_symbols_fd line of a Swift frame reads as its index, image and mangled symbol")
        func paddedSwiftFrame() {
            let line = "12  Example                             0x0000000104a1c3d8 $s7Example11ContentViewV4bodyQrvg5crashyyFyycfU_ + 52"
            let expected = StackFrame(index: 12, image: "Example", symbol: "$s7Example11ContentViewV4bodyQrvg5crashyyFyycfU_")

            let actual = StackFrame(line: line, position: 0)

            #expect(actual == expected)
        }

        @Test("An Objective-C frame keeps the spaces in its instance or class method's symbol")
        func objectiveCFrames() {
            let lines = [
                "3   CoreFoundation                      0x00000001804b8c40 -[NSObject(NSObject) doesNotRecognizeSelector:] + 136",
                "4   CoreFoundation                      0x00000001804b9d0c +[NSException raise:format:arguments:] + 96"
            ]
            let expected = [
                StackFrame(index: 3, image: "CoreFoundation", symbol: "-[NSObject(NSObject) doesNotRecognizeSelector:]"),
                StackFrame(index: 4, image: "CoreFoundation", symbol: "+[NSException raise:format:arguments:]")
            ]

            let actual = StackFrame.frames(lines)

            #expect(actual == expected)
        }

        @Test("A C frame reads as its image and function, without the offset")
        func cFrame() {
            let line = "0   libsystem_kernel.dylib              0x00000001802a1a6c __pthread_kill + 8"
            let expected = StackFrame(index: 0, image: "libsystem_kernel.dylib", symbol: "__pthread_kill")

            let actual = StackFrame(line: line, position: 3)

            #expect(actual == expected)
        }

        @Test("A frame dladdr finds no symbol for shows its image's name, and one with no image either shows 0x0")
        func framesWithoutSymbol() {
            let lines = [
                "5   Example                             0x0000000104a1c3d8 Example + 17368",
                "6   ???                                 0x0000000000000000 0x0 + 0"
            ]
            let expected = [
                StackFrame(index: 5, image: "Example", symbol: "Example"),
                StackFrame(index: 6, image: "???", symbol: "0x0")
            ]

            let actual = StackFrame.frames(lines)

            #expect(actual == expected)
        }

        @Test("An image whose name has spaces, or overflows the padded column, reads whole")
        func wideImages() {
            let lines = [
                "1   My Example App                      0x0000000100004a1c $s14MyExampleApp4mainyyF + 12",
                "2   DebugDrawerCrashReportsPluginPackageTests 0x0000000100008000 main + 4"
            ]
            let expected = [
                StackFrame(index: 1, image: "My Example App", symbol: "$s14MyExampleApp4mainyyF"),
                StackFrame(index: 2, image: "DebugDrawerCrashReportsPluginPackageTests", symbol: "main")
            ]

            let actual = StackFrame.frames(lines)

            #expect(actual == expected)
        }

        @Test("Lines backtrace_symbols_fd writes for this thread read in order, none left whole or with an offset in its symbol")
        func realBacktrace() throws {
            var addresses = [UnsafeMutableRawPointer?](repeating: nil, count: 32)
            let count = Int(backtrace(&addresses, Int32(addresses.count)))
            var descriptors: [Int32] = [-1, -1]
            try #require(pipe(&descriptors) == 0)
            backtrace_symbols_fd(addresses, Int32(count), descriptors[1])
            close(descriptors[1])
            let output = FileHandle(fileDescriptor: descriptors[0], closeOnDealloc: true).readDataToEndOfFile()
            let text = try #require(String(bytes: output, encoding: .utf8))
            let lines = text.split(separator: "\n").map(String.init)
            let expected = Array(0..<count)

            let actual = StackFrame.frames(lines)

            let unread = actual.filter { $0.symbol.contains(" + ") }
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
