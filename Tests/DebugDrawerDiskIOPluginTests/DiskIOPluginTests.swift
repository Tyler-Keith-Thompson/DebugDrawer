#if DEBUG
    @testable import DebugDrawerDiskIOPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct DiskIOPluginTests {
        @Test("Each operation has a word for the filter and VoiceOver")
        func operationNames() {
            let operations: [IOEvent.Operation] = [.read, .write, .delete, .create, .list, .stat, .copy, .move]
            let expected = ["Read", "Write", "Delete", "Create", "List", "Stat", "Copy", "Move"]

            let actual = operations.map(\.name)

            #expect(actual == expected)
        }

        @Test("The plugin is titled Disk I/O, with the drive icon")
        func plugin() {
            let sut = DiskIOPlugin()

            let actual = [sut.title, sut.icon]

            #expect(actual == ["Disk I/O", "externaldrive"])
        }

        @Test("A store with nothing recorded lists nothing under any filter, and counts nothing")
        func emptyStore() {
            let sut = DiskIOStore(recorder: DiskIORecorder())

            sut.filterOp = .read
            let filteredByOperation = sut.filteredEvents
            sut.filterOp = nil
            sut.mainThreadOnly = true
            let filteredByThread = sut.filteredEvents

            #expect(filteredByOperation.isEmpty)
            #expect(filteredByThread.isEmpty)
            #expect(sut.totals == DiskIOTotals())
        }
    }
#endif
