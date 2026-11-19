#if DEBUG
    import Darwin
    @testable import DebugDrawerAppInfoPlugin
    import Testing

    /// A `task_vm_info` reading the test sets, so nothing else the process does moves it.
    private struct FakeTaskVMInfoSource: TaskVMInfoSource {
        let info: task_vm_info_data_t?

        func taskVMInfo() -> task_vm_info_data_t? { info }
    }

    @Suite("App Info memory footprint")
    struct MemoryFootprintTests {
        @Test("The memory shown is phys_footprint, not resident size or the ledger's peak")
        func memoryIsThePhysicalFootprint() {
            let megabyte: UInt64 = 1024 * 1024
            var info = task_vm_info_data_t()
            info.phys_footprint = 300 * megabyte
            info.resident_size = 900 * megabyte
            info.ledger_phys_footprint_peak = Int64(450 * megabyte)
            let source = FakeTaskVMInfoSource(info: info)
            let expected: Double = 300

            let actual = MemoryFootprint.currentMB(from: source)

            #expect(actual == expected)
        }

        @Test("When the kernel won't report task_vm_info, the memory shown is zero")
        func noReadingIsZero() {
            let source = FakeTaskVMInfoSource(info: nil)
            let expected: Double = 0

            let actual = MemoryFootprint.currentMB(from: source)

            #expect(actual == expected)
        }

        @Test("The kernel reports a footprint above zero")
        func kernelReadingIsNonZero() {
            let actual = MemoryFootprint.currentMB()

            #expect(actual > 0)
        }
    }
#endif
