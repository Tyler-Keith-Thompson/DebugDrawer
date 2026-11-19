#if DEBUG
    /// This process's CPU use, and the cores it is measured against.
    ///
    /// The Energy monitor takes it at init and reads it once a sample; `_ProcessCPUReader` reads
    /// the kernel's thread list, and a test passes one it sets by hand.
    @MainActor
    protocol ProcessCPUReader: AnyObject {
        /// The cores the process's threads can use together.
        var processorCount: Int { get }

        /// This process's CPU use now, in percent of one core, summed over its threads.
        func cpuUsage() -> Double
    }
#endif
