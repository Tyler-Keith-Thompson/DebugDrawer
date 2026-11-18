#if DEBUG
    import DebugDrawer
    import Foundation

    /// A volume's size and free space.
    struct DiskSpace: Equatable, Sendable {
        let total: Int64
        let free: Int64

        /// The volume holding the home directory, or `nil` when the system won't say.
        ///
        /// Reads the file system off the caller's actor, as the drawer's own work, so a view asks
        /// for it from a task and never while it draws.
        @concurrent
        static func sample() async -> DiskSpace? {
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
