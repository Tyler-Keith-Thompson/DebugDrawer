#if DEBUG
    /// Reads how big a volume is and how much of it is free.
    ///
    /// The Disk I/O model reads it when the view appears and on Refresh; `_DiskSpaceReading` asks
    /// the file system about the home directory's volume, and a test passes one of its own.
    @MainActor
    protocol DiskSpaceReading {
        /// The volume's size and free space, or `nil` when the system won't say.
        func read() async -> DiskSpace?
    }
#endif
