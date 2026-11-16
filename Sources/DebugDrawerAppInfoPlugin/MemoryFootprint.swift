#if DEBUG
    import Darwin

    /// The process's physical memory footprint: the memory it owns (dirty and compressed pages),
    /// which is what Xcode's memory gauge and the system's memory limits measure.
    enum MemoryFootprint {
        /// The footprint now, in megabytes (MiB), or 0 when the kernel won't report it.
        static func currentMB() -> Double {
            // Resident size would count every clean page mapped in, the system frameworks' shared
            // cache included, several times what the app owns. phys_footprint counts what it owns.
            // The same few lines live in each plugin that shows memory: plugins share no helper target.
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            guard result == KERN_SUCCESS else { return 0 }
            return Double(info.phys_footprint) / (1024 * 1024)
        }
    }
#endif
