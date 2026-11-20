import DebugDrawerHangDetector
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

    @Test("A frame carries its image's UUID and its offset from the image's load address, the same UUID for every address in one image")
    func imageIdentity() throws {
        let strlenSymbol = try #require(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "strlen"))
        let memcpySymbol = try #require(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "memcpy"))
        let mallocSymbol = try #require(dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc"))
        let strlen = UInt(bitPattern: strlenSymbol)
        let memcpy = UInt(bitPattern: memcpySymbol)
        let malloc = UInt(bitPattern: mallocSymbol)
        var info = Dl_info()
        _ = dladdr(UnsafeRawPointer(bitPattern: strlen), &info)
        let strlenBase = UInt64(UInt(bitPattern: info.dli_fbase))

        let actual = Symbolicator.frames(for: [strlen, memcpy + 1, malloc + 1])

        let sameImage = actual.filter { $0.image == actual[0].image }
        let otherImages = actual.filter { $0.image != actual[0].image }
        #expect(actual[0].imageUUID != nil)
        #expect(actual[0].imageLoadAddress == strlenBase)
        #expect(actual[0].imageOffset == UInt64(strlen) - strlenBase)
        #expect(sameImage.allSatisfy { $0.imageUUID == actual[0].imageUUID })
        #expect(otherImages.allSatisfy { $0.imageUUID != nil && $0.imageUUID != actual[0].imageUUID })
    }

    @Test("An address in no image has no image, UUID, offset or symbol")
    func unknownFrame() {
        let actual = Symbolicator.frames(for: [0x10])

        #expect(actual == [PerformanceTraces.Frame(address: 0x10)])
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
