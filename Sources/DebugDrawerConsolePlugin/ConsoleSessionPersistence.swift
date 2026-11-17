#if DEBUG
    import Foundation

    /// How the Console plugin keeps each launch's log lines on disk, so the next launches show
    /// them as previous sessions: how many earlier sessions it keeps, how many bytes all of them
    /// may take, and where.
    ///
    /// Each line is written as it is captured, in batches, on a queue of its own. At launch the
    /// oldest sessions beyond `maxSessions` are deleted, then the oldest until what is kept fits
    /// in `maxBytes`, which is checked again as the current session grows. The current session is
    /// never deleted; a line that would take it alone past `maxBytes` isn't written.
    ///
    /// ```swift
    /// DebugDrawer.shared.installConsole(sessions: ConsoleSessionPersistence(maxSessions: 3, maxBytes: 5_000_000))
    /// ```
    public struct ConsoleSessionPersistence: Sendable {
        /// Keeps 5 earlier sessions in at most 20 MB, in Application Support.
        public static let standard = ConsoleSessionPersistence()

        /// Keeps nothing: no line is written, and the sessions earlier launches kept are deleted
        /// at launch.
        public static let off = ConsoleSessionPersistence(maxSessions: 0)

        /// How many earlier launches' sessions are kept, besides the current one. 0 writes nothing.
        public let maxSessions: Int
        /// How many bytes the earlier sessions and the current one may take together.
        public let maxBytes: Int
        /// Where the sessions are kept.
        public let storage: any ConsoleSessionStorage

        /// - Parameters:
        ///   - maxSessions: How many earlier launches' sessions are kept, besides the current one;
        ///     0 writes nothing and deletes what earlier launches kept.
        ///   - maxBytes: How many bytes the sessions kept may take together, the current one's
        ///     included.
        ///   - storage: Where they are kept; `nil` for files in Application Support, in the
        ///     app's folder under `DebugDrawer/ConsoleSessions`.
        ///
        /// - Precondition: `maxSessions` is 0 or more, and `maxBytes` more than 0.
        public init(maxSessions: Int = 5, maxBytes: Int = 20_000_000, storage: (any ConsoleSessionStorage)? = nil) {
            precondition(maxSessions >= 0, "ConsoleSessionPersistence: maxSessions must be 0 or more")
            precondition(maxBytes > 0, "ConsoleSessionPersistence: maxBytes must be more than 0")
            self.maxSessions = maxSessions
            self.maxBytes = maxBytes
            self.storage = storage ?? _ConsoleSessionStorage(directory: _ConsoleSessionStorage.defaultDirectory)
        }

        /// Whether lines are written at all.
        var isOn: Bool {
            maxSessions > 0
        }
    }
#endif
