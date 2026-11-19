#if DEBUG
    import Foundation

    /// The console's lines as a value: what was captured, the filter that picks the lines listed,
    /// and the earlier session shown under Previous. ``ConsoleLogStore`` holds it;
    /// ``ConsoleSnapshot`` carries it to the view.
    struct ConsoleLogSnapshot: Codable, Equatable, Sendable {
        /// The captured lines, oldest first.
        var lines: [LogLine] = []
        /// How many older lines the bounds dropped since the store was made or last cleared.
        var droppedLineCount = 0
        /// Which lines the console lists.
        var filter = ConsoleFilter()
        /// The search field's text.
        var searchText = ""
        /// Whether `searchText` is a regular expression.
        var searchIsRegularExpression = false
        /// Why `searchText` isn't a pattern, while it isn't one.
        var searchIssue: ConsoleSearch.InvalidPattern?
        /// What went wrong reading or saving the mutes.
        var muteIssue: ConsoleMuteIssue?
        /// Whether the console shows the captured lines or an earlier session's.
        var source = ConsoleLogSource.captured
        /// The page of the earlier session shown under Previous, once one is read.
        var previousPage: ConsoleSessionPage?

        /// The captured lines the level, search, mutes and time range pass.
        var filteredLines: [LogLine] {
            filter.apply(to: lines)
        }

        /// The lines the console lists: the captured ones the filter passes, or, under Previous,
        /// the earlier session's page of them.
        var shownLines: [LogLine] {
            switch source {
            case .captured: filteredLines
            case .previous: previousPage?.lines ?? []
            }
        }

        /// How many of the source's lines the mutes hide, of those the other filters pass; while
        /// the filter shows muted lines, how many they would hide.
        var mutedCount: Int {
            switch source {
            case .captured: filter.mutedCount(in: lines)
            case .previous: previousPage?.mutedCount ?? 0
            }
        }

        /// The mutes the menu offers for the source's lines.
        var muteChoices: [ConsoleMute] {
            switch source {
            case .captured: ConsoleMute.choices(in: lines, excluding: filter.mutes)
            case .previous: previousPage?.muteChoices ?? []
            }
        }

        /// The session an earlier launch kept that shows under Previous, once one is read.
        var previousLog: ConsoleSessionLog? {
            previousPage?.log
        }
    }
#endif
