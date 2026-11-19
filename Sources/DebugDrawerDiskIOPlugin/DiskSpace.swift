#if DEBUG
    /// A volume's size and free space, in bytes.
    struct DiskSpace: Codable, Equatable, Sendable {
        let total: Int64
        let free: Int64
    }
#endif
