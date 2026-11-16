#if DEBUG
    @testable import DebugDrawerHangDetectorPlugin
    import Foundation
    import Testing

    @Suite
    struct SymbolicatorTests {
        @Test("An address in an exported function names its image, address, symbol and offset")
        func exported() throws {
            let symbol = try #require(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "strlen"))
            let address = UInt(bitPattern: symbol) + 4

            let actual = try #require(Symbolicator.lines(for: [address]).first)

            #expect(actual.hasPrefix("0 libsystem_platform.dylib 0x") || actual.hasPrefix("0 libsystem_c.dylib 0x"))
            #expect(actual.hasSuffix(" _platform_strlen + 4") || actual.hasSuffix(" strlen + 4"))
        }

        @Test("A return address is looked up a byte earlier, so a call that ends a function names that function")
        func returnAddress() throws {
            let symbol = try #require(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "strlen"))
            let start = UInt(bitPattern: symbol)

            let actual = Symbolicator.lines(for: [start, start])

            #expect(actual.first?.hasSuffix("strlen + 0") == true)
            #expect(actual.last?.contains("strlen") == false)
            #expect(actual.last?.hasPrefix("1 ") == true)
        }

        @Test("An address in no image is named ???, with its address")
        func unknown() {
            let actual = Symbolicator.lines(for: [0x10])

            #expect(actual == ["0 ??? 0x0000000000000010"])
        }

        @Test("No addresses name nothing")
        func empty() {
            let actual = Symbolicator.lines(for: [])

            #expect(actual.isEmpty)
        }
    }
#endif
