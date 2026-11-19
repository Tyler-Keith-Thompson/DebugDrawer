#if DEBUG
    import Darwin
    @testable import DebugDrawerPerformancePlugin
    import Testing

    /// A `task_vm_info` reading the test sets, so nothing else the process does moves it.
    private struct FakeTaskVMInfoSource: TaskVMInfoSource {
        let info: task_vm_info_data_t?

        func taskVMInfo() -> task_vm_info_data_t? { info }
    }

    @Suite("Performance memory footprint")
    struct MemoryFootprintTests {
        @Test("The footprint is phys_footprint and the peak is the ledger's peak, not resident size")
        func footprintIsPhysicalFootprintAndPeakIsLedgerPeak() {
            let megabyte: UInt64 = 1024 * 1024
            var info = task_vm_info_data_t()
            info.phys_footprint = 300 * megabyte
            info.resident_size = 900 * megabyte
            info.ledger_phys_footprint_peak = Int64(450 * megabyte)
            let source = FakeTaskVMInfoSource(info: info)
            let expected = MemoryFootprint(megabytes: 300, peakMegabytes: 450)

            let actual = MemoryFootprint.current(from: source)

            #expect(actual == expected)
        }

        @Test("A ledger peak below the footprint, as an older kernel leaves it, reads as the footprint")
        func peakIsNeverBelowTheFootprint() {
            let megabyte: UInt64 = 1024 * 1024
            var info = task_vm_info_data_t()
            info.phys_footprint = 300 * megabyte
            info.resident_size = 900 * megabyte
            info.ledger_phys_footprint_peak = 0
            let source = FakeTaskVMInfoSource(info: info)
            let expected = MemoryFootprint(megabytes: 300, peakMegabytes: 300)

            let actual = MemoryFootprint.current(from: source)

            #expect(actual == expected)
        }

        @Test("When the kernel won't report task_vm_info, the footprint and its peak are zero")
        func noReadingIsZero() {
            let source = FakeTaskVMInfoSource(info: nil)
            let expected = MemoryFootprint(megabytes: 0, peakMegabytes: 0)

            let actual = MemoryFootprint.current(from: source)

            #expect(actual == expected)
        }

        @Test("The kernel reports a footprint above zero, and a peak no lower than it")
        func kernelReadingIsNonZero() {
            let actual = MemoryFootprint.current()

            #expect(actual.megabytes > 0)
            #expect(actual.peakMegabytes >= actual.megabytes)
        }

        @Test("The peak holds a spike that is gone by the next reading")
        func peakHoldsASpike() throws {
            let before = MemoryFootprint.current()
            // 64 MB written, so the pages are dirty and count, then freed.
            let spikeBytes = 64 * 1024 * 1024
            let spike = try #require(malloc(spikeBytes))
            memset(spike, 1, spikeBytes)
            free(spike)
            let expectedAtLeast = before.megabytes + 60

            let actual = MemoryFootprint.current().peakMegabytes

            #expect(actual >= expectedAtLeast, "peak \(actual) MB, footprint before the spike \(before.megabytes) MB")
        }
    }
#endif
