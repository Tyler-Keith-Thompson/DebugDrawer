#if DEBUG
    /// Where the Deep Link Tester keeps the URLs it opened and the activities it continued, so they
    /// outlast a relaunch.
    @MainActor
    protocol DeepLinkHistoryStore {
        /// The history kept; empty when none is, or when what is kept no longer reads.
        func load() -> DeepLinkHistory
        /// Keeps `history` in place of what was kept.
        func save(_ history: DeepLinkHistory)
    }
#endif
