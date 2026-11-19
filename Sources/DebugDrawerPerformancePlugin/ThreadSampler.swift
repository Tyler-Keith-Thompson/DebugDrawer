#if DEBUG
    /// Reads the process's threads and the CPU each is using. Tests pass a fixed list instead.
    protocol ThreadSampler {
        /// The process's threads now, busiest first.
        func sample() -> [ThreadCPU]
    }
#endif
