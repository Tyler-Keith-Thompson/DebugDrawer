#if DEBUG
    import Foundation

    /// How a captured request is linked to others by replay: the request it resends, and the
    /// requests that resent it. Its detail shows both and selects either.
    struct NetworkReplayLinks {
        /// The request this one resends, when it is a replay and its original is still in the log.
        var original: NetworkEntry?
        /// The ids of the requests that resent this one, newest first.
        var replays: [NetworkEntry.ID] = []

        /// No links: a request that isn't a replay and was never resent.
        static let none = NetworkReplayLinks()

        /// The links of `entry` among `entries`, which are newest first, as the log keeps them.
        ///
        /// - Complexity: O(*n*) in the number of entries.
        init(of entry: NetworkEntry, in entries: [NetworkEntry]) {
            original = entry.replayOf.flatMap { id in entries.first { $0.id == id } }
            replays = entries.filter { $0.replayOf == entry.id }.map(\.id)
        }

        private init() {}
    }
#endif
