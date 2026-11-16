#if DEBUG
    /// An identifier the Info.plist's `BGTaskSchedulerPermittedIdentifiers` lists.
    struct PermittedIdentifier: Identifiable, Hashable, Sendable {
        /// The identifier, as listed.
        let id: String

        init(_ id: String) {
            self.id = id
        }

        /// Whether it ends in `*`: a prefix for continued processing tasks, which the app starts
        /// itself while in front, rather than one task the system launches.
        var isWildcard: Bool {
            id.hasSuffix("*")
        }
    }
#endif
