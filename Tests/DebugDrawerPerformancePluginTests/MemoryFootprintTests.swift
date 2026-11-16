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

            let actual = MemoryFootprint.currentMB()

            #expect(abs(actual - expected) <= tolerance, "\(actual) MB against phys_footprint \(expected) MB")
        }
    }
#endif
