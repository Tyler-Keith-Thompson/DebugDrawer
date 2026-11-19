#if DEBUG
    import Darwin

    /// The process's physical memory footprint: the memory it owns (dirty and compressed pages),
    /// which is what Xcode's memory gauge and the system's memory limits measure.
    enum MemoryFootprint {
        /// The footprint now, in megabytes (MiB), or 0 when the kernel won't report it.
        ///
        /// - Parameter source: where the process's `task_vm_info` comes from; the kernel by default.
        static func currentMB(from source: some TaskVMInfoSource = _TaskVMInfoSource()) -> Double {
            // Resident size would count every clean page mapped in, the system frameworks' shared
            // cache included, several times what the app owns. phys_footprint counts what it owns.
            guard let info = source.taskVMInfo() else { return 0 }
            return Double(info.phys_footprint) / (1024 * 1024)
        }
    }
#endif
