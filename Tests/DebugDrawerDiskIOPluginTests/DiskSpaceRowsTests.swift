// Views are inspected on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS) && DEBUG
    @testable import DebugDrawerDiskIOPlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite
    struct DiskSpaceRowsTests {
        @Test("The disk rows show what the volume they're given holds, the same each time it's drawn")
        func pureFunctionOfVolume() throws {
            let volume = DiskSpace(total: 1_000 * 1024 * 1024 * 1024, free: 100 * 1024 * 1024 * 1024)
            let sut = DiskSpaceRows(volume: volume)

            let first = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }
            let second = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(first.contains("90%"))
            #expect(first.contains("100.0 GB"))
            #expect(first == second)
        }

        @Test("Another volume draws other figures: what the rows show comes from their input alone")
        func otherVolume() throws {
            let full = DiskSpaceRows(volume: DiskSpace(total: 1024 * 1024 * 1024, free: 1024 * 1024 * 10))
            let empty = DiskSpaceRows(volume: DiskSpace(total: 1024 * 1024 * 1024, free: 1024 * 1024 * 1024))

            let fullTexts = try full.inspect().findAll(ViewType.Text.self).map { try $0.string() }
            let emptyTexts = try empty.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(fullTexts.contains("99%"))
            #expect(emptyTexts.contains("0%"))
            #expect(emptyTexts.contains("1.0 GB"))
        }

        @Test("With no volume sampled yet, the rows draw nothing")
        func noVolume() throws {
            let sut = DiskSpaceRows(volume: nil)

            let actual = try sut.inspect().findAll(ViewType.Text.self)

            #expect(actual.isEmpty)
        }
    }
#endif
