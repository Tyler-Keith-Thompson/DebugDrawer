#if DEBUG
    @testable import DebugDrawerDeepLinkPlugin

    /// A history store in memory: it starts with what it's given, and keeps each save, in order.
    @MainActor
    final class FakeDeepLinkHistoryStore: DeepLinkHistoryStore {
        /// What a load returns: the last save, or what the store started with.
        private(set) var kept: DeepLinkHistory
        /// Every history saved, oldest first.
        private(set) var saved: [DeepLinkHistory] = []

        init(_ kept: DeepLinkHistory = DeepLinkHistory()) {
            self.kept = kept
        }

        func load() -> DeepLinkHistory {
            kept
        }

        func save(_ history: DeepLinkHistory) {
            saved.append(history)
            kept = history
        }
    }
#endif
