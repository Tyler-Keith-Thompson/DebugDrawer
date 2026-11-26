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
/// try DebugDrawer.shared.installConsole(sessions: ConsoleSessionPersistence(maxSessions: 3, maxBytes: 5_000_000))
/// ```
public struct ConsoleSessionPersistence: Sendable {
    /// Keeps 5 earlier sessions in at most 20 MB, in Application Support.
    public static let standard = ConsoleSessionPersistence(uncheckedMaxSessions: 5, maxBytes: 20_000_000, storage: nil)

    /// Keeps nothing: no line is written, and the sessions earlier launches kept are deleted
    /// at launch.
    public static let off = ConsoleSessionPersistence(uncheckedMaxSessions: 0, maxBytes: 20_000_000, storage: nil)

    /// A bound a session persistence can't take.
    public enum InvalidLimit: Error, Equatable, Sendable {
        /// The number of earlier sessions kept is negative.
        case negativeMaxSessions
        /// The bytes the sessions may take is 0 or less.
        case nonPositiveMaxBytes
    }

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
    /// - Throws: ``InvalidLimit/negativeMaxSessions`` when `maxSessions` is negative, and
    ///   ``InvalidLimit/nonPositiveMaxBytes`` when `maxBytes` is 0 or less.
    public init(maxSessions: Int = 5, maxBytes: Int = 20_000_000, storage: (any ConsoleSessionStorage)? = nil) throws(InvalidLimit) {
        guard maxSessions >= 0 else { throw .negativeMaxSessions }
        guard maxBytes > 0 else { throw .nonPositiveMaxBytes }
        self.init(uncheckedMaxSessions: maxSessions, maxBytes: maxBytes, storage: storage)
    }

    /// Persistence the caller knows is valid: ``standard`` and ``off``, constants no input reaches.
    private init(uncheckedMaxSessions maxSessions: Int, maxBytes: Int, storage: (any ConsoleSessionStorage)?) {
        self.maxSessions = maxSessions
        self.maxBytes = maxBytes
        #if DEBUG
            self.storage = storage ?? _ConsoleSessionStorage(directory: _ConsoleSessionStorage.defaultDirectory)
        #else
            self.storage = storage ?? NoConsoleSessionStorage()
        #endif
    }

    /// Whether lines are written at all.
    var isOn: Bool {
        maxSessions > 0
    }
}

#if !DEBUG
    /// Release builds write no sessions, so the default storage keeps nothing.
    private struct NoConsoleSessionStorage: ConsoleSessionStorage {
        func sessionFiles() throws -> [ConsoleSessionFile] {
            []
        }

        func append(_: Data, toSessionNamed _: String) throws {}

        func contents(ofSessionNamed _: String) throws -> Data {
            Data()
        }

        func deleteSession(named _: String) throws {}
    }
#endif
