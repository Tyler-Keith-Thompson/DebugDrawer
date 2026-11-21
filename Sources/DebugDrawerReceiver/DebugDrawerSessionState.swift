import Foundation

// What `DebugDrawerSessions` publishes, and what a sidecar sends it, as plain values: they cross
// the transports as JSON, so a viewer connects to the sessions as it would to any plugin's model,
// and they hold nothing secret (an ID, two dates and, with a grant, what it allows, never the
// token: the sidecar sends that once, with `open`, and it is never written back). Real in every build: values do nothing by
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
    /// ``DebugDrawerSessions/maximumDuration`` after ``opened``, and no later than its
    /// ``grant``'s expiry.
    public let expires: Date
    /// The grant it opened with, when the sessions have a ``DebugDrawerGrantPolicy``: who holds
    /// it and the capabilities it covers. `nil` without a policy.
    public let grant: DebugDrawerGrant?

    /// A session.
    ///
    /// - Parameters:
    ///   - id: Tells it from other sessions.
    ///   - opened: When it opened.
    ///   - expires: When it expires.
    ///   - grant: The grant it opened with, if any.
    public init(id: UUID, opened: Date, expires: Date, grant: DebugDrawerGrant? = nil) {
        self.id = id
        self.opened = opened
        self.expires = expires
        self.grant = grant
    }
}

// The sessions check a grant only against commands. The receiver asks this before it writes any
// capability's snapshot to the store (DebugDrawerReceiver+SessionServing.swift), so a grant meant
// for one capability doesn't expose another's data; a capability whose point is what it collects
// for a session (push registration, app state, analytics events, MetricKit payloads) also asks it
// before collecting anything, as it may be served by something other than a receiver. Without a
// grant (no policy) every session is served, as every command in one is applied, unless the
// capability requires a grant.
extension DebugDrawerSession {
    /// Whether `capability` may serve this session what it holds: always for a session without a
    /// grant, and otherwise only when its grant lists `capability`.
    ///
    /// - Parameter capability: The ID the capability's model is served under.
    /// - Returns: Whether to serve the session.
    package func allows(_ capability: String) -> Bool {
        allows(capability, requiringGrant: false)
    }

    /// Whether `capability` may serve this session what it holds, for a capability that may need
    /// a grant even without a policy (`requiringGrant()`): only when the session's grant lists
    /// `capability`, and for a session without a grant only when `requiresGrant` is `false`.
    ///
    /// - Parameters:
    ///   - capability: The ID the capability's model is served under.
    ///   - requiresGrant: Whether the capability needs a grant listing it in every session.
    /// - Returns: Whether to serve the session.
    package func allows(_ capability: String, requiringGrant requiresGrant: Bool) -> Bool {
        grant.map { $0.capabilities.contains(capability) } ?? !requiresGrant
    }
}

/// What a sidecar asks of ``DebugDrawerSessions``.
public enum DebugDrawerSessionCommand: Codable, Equatable, Sendable {
    /// Opens a session lasting `duration` seconds, or the host's maximum if that is shorter.
    /// Refused while a session is open, and for a duration that isn't a positive number.
    ///
    /// When the sessions have a ``DebugDrawerGrantPolicy``, `grant` is the token the company's
    /// server issued, and the session opens only if it is valid, then lasts no longer than it
    /// does. Without a policy `grant` is ignored. A sidecar that sends none encodes the command
    /// as one from before grants existed.
    case open(duration: TimeInterval, grant: String? = nil)
    /// Ends the open session, reverting its session-scoped changes.
    case end
}
