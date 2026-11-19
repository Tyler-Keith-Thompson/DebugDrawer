#if DEBUG
    /// The URLs opened and the activities continued, each most recent first.
    struct DeepLinkHistory: Hashable, Codable, Sendable {
        /// URLs opened, most recent first.
        var urls: [String] = []
        /// Activities continued, most recent first.
        var activities: [DeepLinkActivity] = []
    }
#endif
