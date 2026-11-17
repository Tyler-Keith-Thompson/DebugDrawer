#if DEBUG
    import Foundation

    /// Which lines the console lists: the lowest level, the search, the muted subsystems and
    /// categories, and the time range, each of which a line must pass.
    ///
    /// The mutes hide what they match unless `showsMuted`, which turns them off for now without
    /// forgetting them, so a mute never hides lines without the console saying how many.
    struct ConsoleFilter: Equatable {
        /// The lowest level shown.
        var level = LogLine.Level.debug
        /// What a line's text, subsystem or category must match.
        var search = ConsoleSearch.all
        /// The subsystems and categories hidden, in the order they were muted.
        var mutes: [ConsoleMute] = []
        /// Whether the muted lines show anyway, for now.
        var showsMuted = false
        /// When a line must be logged to show.
        var timeRange = ConsoleTimeRange.all

        /// The lines of `lines` the filter passes, in order.
        ///
        /// - Complexity: O(*n*) in the number of lines, times the mutes' count and the search.
        func apply(to lines: [LogLine]) -> [LogLine] {
            let start = timeRange.start(newest: lines.newestTimestamp)
            let hidesMuted = !showsMuted && !mutes.isEmpty
            return lines.filter { line in
                passesAllButMutes(line, from: start) && !(hidesMuted && mutes.mutes(line))
            }
        }

        /// How many lines of `lines` the mutes hide, of those the level, search and time range
        /// pass; while `showsMuted`, how many they would hide.
        func mutedCount(in lines: [LogLine]) -> Int {
            guard !mutes.isEmpty else { return 0 }
            let start = timeRange.start(newest: lines.newestTimestamp)
            return lines.count { mutes.mutes($0) && passesAllButMutes($0, from: start) }
        }

        /// Whether `line` passes the level, the search and the time range, which starts at `start`.
        private func passesAllButMutes(_ line: LogLine, from start: Date?) -> Bool {
            line.level >= level && (start.map { line.timestamp >= $0 } ?? true) && search.matches(line)
        }
    }

    extension [LogLine] {
        /// When the newest line was logged; `nil` for no lines. Lines from stdout and os_log can
        /// arrive a little out of order, so it is the latest time rather than the last line's.
        fileprivate var newestTimestamp: Date? {
            lazy.map(\.timestamp).max()
        }
    }
#endif
