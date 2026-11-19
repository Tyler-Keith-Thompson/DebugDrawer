import Foundation

// Public because it is `ConsoleModel`'s `Snapshot`, and opaque: its fields stay internal, so the
// plugin's types (a mute, a session's page) don't become API. A reader outside the module carries
// it whole, encoded.

#if DEBUG
    /// Everything the Console plugin shows, as a value: the captured lines with the filter that
    /// picks those listed, or an earlier session's page of them, and the earlier sessions kept.
    ///
    /// ``ConsoleModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport can
    /// carry it to another process.
    public struct ConsoleSnapshot: Codable, Equatable, Sendable {
        /// The lines, the filter, the search and the mutes.
        var log = ConsoleLogSnapshot()
        /// The sessions earlier launches kept, the newest first.
        var sessions: [ConsoleSessionSummary] = []
        /// The session last asked for that couldn't be read.
        var unreadableSession: ConsoleSessionSummary?
    }
#else
    /// Release builds capture nothing: this stand-in holds nothing.
    public struct ConsoleSnapshot: Codable, Equatable, Sendable {}
#endif
