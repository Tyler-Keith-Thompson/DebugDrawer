#if DEBUG
    /// An earlier session as the console lists it under Previous: the newest lines the filter
    /// passes, up to a limit, with what the mutes hide and offer.
    ///
    /// A session can hold up to `ConsoleSessionPersistence.maxBytes` of lines, about 100,000 at
    /// 20 MB, so the console draws a page of it rather than all of it: drawing a line's text takes
    /// about as long as decoding it, and the text view draws on the main actor. The page is
    /// worked out off the main actor when a session opens (``prepared(log:filter:)``), so opening
    /// hands the main actor a page whose size doesn't depend on the session's.
    struct ConsoleSessionPage: Sendable {
        /// How many lines a page starts with, and how many more each Show Earlier adds: as many as
        /// the console keeps of the current session.
        static let lineCount = 2000

        /// The session.
        let log: ConsoleSessionLog
        /// The filter the lines passed.
        let filter: ConsoleFilter
        /// How many of the newest matching lines the page lists.
        let lineLimit: Int
        /// The lines the filter passes, oldest first.
        private let matching: [LogLine]
        /// The newest `lineLimit` lines the filter passes, oldest first.
        let lines: [LogLine]
        /// How many lines the mutes hide, of those the other filters pass; while
        /// `filter.showsMuted`, how many they would hide.
        let mutedCount: Int
        /// The mutes the menu offers for the session's lines.
        let muteChoices: [ConsoleMute]

        /// The page of `log` that `filter` passes, its newest `lineLimit` lines.
        ///
        /// - Complexity: O(*n*) in the session's lines, times the mutes' count and the search.
        /// - Precondition: `lineLimit` is more than 0.
        init(log: ConsoleSessionLog, filter: ConsoleFilter, lineLimit: Int = Self.lineCount) {
            precondition(lineLimit > 0, "ConsoleSessionPage: lineLimit must be more than 0")
            let matching = filter.apply(to: log.lines)
            self.init(
                log: log, filter: filter, lineLimit: lineLimit, matching: matching,
                mutedCount: filter.mutedCount(in: log.lines),
                muteChoices: ConsoleMute.choices(in: log.lines, excluding: filter.mutes)
            )
        }

        private init(
            log: ConsoleSessionLog, filter: ConsoleFilter, lineLimit: Int, matching: [LogLine], mutedCount: Int, muteChoices: [ConsoleMute]
        ) {
            self.log = log
            self.filter = filter
            self.lineLimit = lineLimit
            self.matching = matching
            lines = Array(matching.suffix(lineLimit))
            self.mutedCount = mutedCount
            self.muteChoices = muteChoices
        }

        /// The page of `log` that `filter` passes, worked out off the main actor.
        ///
        /// - Complexity: O(*n*) in the session's lines, none of it on the caller's actor.
        @concurrent
        static func prepared(log: ConsoleSessionLog, filter: ConsoleFilter) async -> ConsoleSessionPage {
            ConsoleSessionPage(log: log, filter: filter)
        }

        /// How many older lines the filter passes that the page doesn't list.
        var earlierCount: Int {
            matching.count - lines.count
        }

        /// The page with up to ``lineCount`` more of the earlier matching lines.
        ///
        /// - Complexity: O(*k*) in the lines the new page lists; the filter doesn't run again.
        func showingEarlier() -> ConsoleSessionPage {
            ConsoleSessionPage(
                log: log, filter: filter, lineLimit: lineLimit + Self.lineCount, matching: matching,
                mutedCount: mutedCount, muteChoices: muteChoices
            )
        }

        /// The same session through `filter`, as many lines listed as now.
        ///
        /// - Complexity: O(*n*) in the session's lines, times the mutes' count and the search.
        func filtered(by filter: ConsoleFilter) -> ConsoleSessionPage {
            ConsoleSessionPage(log: log, filter: filter, lineLimit: lineLimit)
        }
    }
#endif
