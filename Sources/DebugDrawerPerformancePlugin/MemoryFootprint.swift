#if DEBUG
    import Darwin

    /// The process's physical memory footprint: the memory it owns (dirty and compressed pages),
    /// which is what Xcode's memory gauge and the system's memory limits measure.
    struct MemoryFootprint: Equatable {
        /// The footprint now, in megabytes (MiB).
        let megabytes: Double
        /// The highest footprint since the process started, in megabytes (MiB).
        let peakMegabytes: Double

        /// The footprint now and its peak, or zero for both when the kernel won't report them.
        ///
        /// - Parameter source: where the process's `task_vm_info` comes from; the kernel by default.
        static func current(from source: some TaskVMInfoSource = _TaskVMInfoSource()) -> MemoryFootprint {
            // Resident size would count every clean page mapped in, the system frameworks' shared
            // cache included, several times what the app owns. phys_footprint counts what it owns,
            // and the kernel's ledger keeps its peak over the process's life, so the peak holds a
            // spike between two samples and from before the drawer opened.
            guard let info = source.taskVMInfo() else { return MemoryFootprint(megabytes: 0, peakMegabytes: 0) }
            let megabyte = 1024.0 * 1024.0
            let footprint = Double(info.phys_footprint) / megabyte
            // The peak is in the structure's later revisions; an older kernel fills fewer fields,
            // and the footprint itself is then the best peak known.
            let peak = Double(info.ledger_phys_footprint_peak) / megabyte
            return MemoryFootprint(megabytes: footprint, peakMegabytes: max(peak, footprint))
        }
    }
#endif
