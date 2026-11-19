import Foundation

// What `DebugDrawerSessions` publishes, and what a sidecar sends it, as plain values: they cross
// the transports as JSON, so a viewer connects to the sessions as it would to any plugin's model,
// and they hold nothing secret (an ID and two dates). Real in every build: values do nothing by
// themselves, and a host's indicator reads `isActive` unchanged in release, where it is never
// true.

/// Whether a sidecar's session is open, and until when.
///
/// ``DebugDrawerSessions`` publishes it as its ``DebugDrawerSessions/snapshot``. Show the person
/// holding the device that debug tooling is engaged for as long as it is ``active(_:)``.
public enum DebugDrawerSessionState: Codable, Equatable, Sendable {
    /// No session is open: every command from outside the process is refused.
    case inactive
    /// A session is open, and commands to the capabilities the host declared are applied.
    case active(DebugDrawerSession)

    /// Whether a session is open.
    public var isActive: Bool {
        session != nil
    }

    /// The open session, or `nil` when none is.
    public var session: DebugDrawerSession? {
        switch self {
        case .inactive: nil
        case let .active(session): session
        }
    }
}

/// One session a sidecar opened.
public struct DebugDrawerSession: Codable, Equatable, Sendable {
    /// Tells this session's entries in the audit log from another's.
    public let id: UUID
    /// When it opened.
    public let opened: Date
    /// When it expires, unless it ends first: at most the host's
    /// ``DebugDrawerSessions/maximumDuration`` after ``opened``.
    public let expires: Date

    /// A session.
    ///
    /// - Parameters:
    ///   - id: Tells it from other sessions.
    ///   - opened: When it opened.
    ///   - expires: When it expires.
    public init(id: UUID, opened: Date, expires: Date) {
        self.id = id
        self.opened = opened
        self.expires = expires
    }
}

/// What a sidecar asks of ``DebugDrawerSessions``.
public enum DebugDrawerSessionCommand: Codable, Equatable, Sendable {
    /// Opens a session lasting `duration` seconds, or the host's maximum if that is shorter.
    /// Refused while a session is open, and for a duration that isn't a positive number.
    case open(duration: TimeInterval)
    /// Ends the open session, reverting its session-scoped changes.
    case end
}
