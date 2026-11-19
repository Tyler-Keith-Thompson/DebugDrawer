#if DEBUG
    import DebugDrawer
    import Foundation

    /// The volume holding the home directory, read from the file system.
    struct _DiskSpaceReading: DiskSpaceReading {
        func read() async -> DiskSpace? {
            await Self.homeVolume()
        }

        /// Reads the file system off the main actor, as the drawer's own work, so the main thread
        /// never waits on the disk.
        @concurrent
        private static func homeVolume() async -> DiskSpace? {
            DebugDrawerActivity.$isDrawerWork.withValue(true) {
                guard let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
                      let total = attributes[.systemSize] as? Int64,
                      let free = attributes[.systemFreeSize] as? Int64,
                      total > 0 else { return nil }
                return DiskSpace(total: total, free: free)
            }
        }
    }
#endif
