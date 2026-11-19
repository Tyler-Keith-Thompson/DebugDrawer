#if DEBUG
    @testable import DebugDrawerHangDetectorPlugin
    import Testing

    struct SymbolDemanglerTests {
        @Test("Swift's demangler names a function, a method, a closure and a generic function as Xcode does",
              arguments: [
                  ("$s7Example5crashyyF", "Example.crash() -> ()"),
                  ("$s7Example11ContentViewV5crashyyF", "Example.ContentView.crash() -> ()"),
                  ("$s7Example11ContentViewV4bodyQrvgyycfU_", "closure #1 () -> () in Example.ContentView.body.getter : some"),
                  ("$s7Example5firstyxSayxGlF", "Example.first<A>(Swift.Array<A>) -> A")
              ])
        func swiftSymbols(symbol: String, expected: String) {
            let sut = _SymbolDemangler()

            let actual = sut.demangle(symbol)

            #expect(actual == expected)
        }

        @Test("Swift's demangler names no Objective-C or C symbol, an address or an image, so their frames keep them",
              arguments: [
                  "-[NSObject(NSObject) doesNotRecognizeSelector:]",
                  "+[NSException raise:format:arguments:]",
                  "__pthread_kill",
                  "main",
                  "0x100004000 + 16384",
                  "Example"
              ])
        func otherSymbols(symbol: String) {
            let sut = _SymbolDemangler()
            let frame = StackFrame(index: 3, image: "CoreFoundation", symbol: symbol)

            let actual = frame.demangled(by: sut)

            #expect(sut.demangle(symbol) == nil)
            #expect(actual == frame)
        }

        @Test("A frame's mangled Swift symbol reads as Xcode names it, with its index and image kept")
        func demangledFrame() {
            let line = "1 Example 0x0000000100004a1c $s7Example5crashyyF + 48"
            let expected = StackFrame(index: 1, image: "Example", symbol: "Example.crash() -> ()")

            let actual = StackFrame(line: line, position: 0).demangled(by: _SymbolDemangler())

            #expect(actual == expected)
        }

        @Test("Without a demangler to ask, a frame keeps its mangled symbol")
        func noDemangler() {
            struct UnresolvedDemangler: SymbolDemangler {
                func demangle(_ symbol: String) -> String? {
                    nil
                }
            }
            let line = "1 Example 0x0000000100004a1c $s7Example5crashyyF + 48"
            let expected = StackFrame(index: 1, image: "Example", symbol: "$s7Example5crashyyF")

            let actual = StackFrame(line: line, position: 0).demangled(by: UnresolvedDemangler())

            #expect(actual == expected)
        }
    }
#endif
