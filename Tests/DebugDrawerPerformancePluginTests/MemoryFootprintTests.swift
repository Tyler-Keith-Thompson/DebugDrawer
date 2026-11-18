#if DEBUG
    import Darwin
    @testable import DebugDrawerPerformancePlugin
    import Testing

    @Suite("Performance memory footprint")
    struct MemoryFootprintTests {
        @Test("The footprint Performance samples is the process's phys_footprint, within 5%")
        func memoryIsThePhysicalFootprint() throws {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            try #require(result == KERN_SUCCESS)
            let expected = Double(info.phys_footprint) / (1024 * 1024)
            let tolerance = expected * 0.05

            let actual = MemoryFootprint.current().megabytes

            #expect(abs(actual - expected) <= tolerance, "\(actual) MB against phys_footprint \(expected) MB")
        }

        @Test("The peak is the kernel's lifetime phys_footprint peak, within 5%, and never below the footprint")
        func peakIsTheLedgerPeak() throws {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            try #require(result == KERN_SUCCESS)
            let expected = Double(info.ledger_phys_footprint_peak) / (1024 * 1024)
            let tolerance = expected * 0.05

            let actual = MemoryFootprint.current()

            #expect(abs(actual.peakMegabytes - expected) <= tolerance, "\(actual.peakMegabytes) MB against the ledger's \(expected) MB")
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
