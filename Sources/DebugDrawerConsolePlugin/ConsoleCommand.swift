import Foundation

// Public because it is `ConsoleModel`'s `Command`, and opaque: the actions it wraps stay internal,
// as their payloads (a mute, a time range) are the plugin's own types. An enum's cases share its
// access level, so the public type is a struct around the internal enum.

#if DEBUG
    /// Something the Console plugin's view asks ``ConsoleModel`` to do: change the filter or the
    /// search, mute a subsystem, clear the lines, open an earlier session. `Codable`, so a
    /// transport can carry it from another process.
    public struct ConsoleCommand: Codable, Sendable {
        /// What to do, by the part of the plugin it changes.
        enum Action: Codable, Sendable {
            case filter(Filter)
            case lines(Lines)
            case sessions(Sessions)
        }

        /// A change to which lines the console lists: the level, the search, the time range and
        /// the mutes.
        enum Filter: Codable, Sendable {
            case setSearchText(String)
            case setSearchIsRegularExpression(Bool)
            case setLevel(LogLine.Level)
            case setTimeRange(ConsoleTimeRange)
            case setShowsMuted(Bool)
            case mute(ConsoleMute)
            case unmute(ConsoleMute)
            case unmuteAll
        }

        /// A change to the lines the console shows.
        enum Lines: Codable, Sendable {
            case setSource(ConsoleLogSource)
            /// Clears the captured lines, or, under Previous, deletes the session shown.
            case clearShown
            /// Lists more of the earlier session's older lines.
            case showEarlier
        }

        /// A change to the sessions earlier launches kept.
        enum Sessions: Codable, Sendable {
            case reload
            case show(ConsoleSessionSummary.ID)
            case delete([ConsoleSessionSummary.ID])
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds capture nothing: this stand-in asks for nothing.
    public struct ConsoleCommand: Codable, Sendable {}
#endif
