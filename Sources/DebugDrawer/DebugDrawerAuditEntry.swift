import Foundation

// One line of the audit log, as a value the host can keep, encode and forward: when, which
// session, which capability, and what happened. It never holds a command's payload: a command
// can carry a value the host wouldn't want written down (a defaults value, a flag's string), so
// the log names the capability that was driven and the outcome, never what was asked. Rejected:
// the payload, or a description of it (`String(describing:)` of a command shows its values); a
// free-text message (a forwarder couldn't tell an applied command from a refused one without
// parsing it).

/// One event of the sidecar's sessions: a session opening or ending, a command applied or
/// refused, or a session-scoped change reverted.
///
/// ``DebugDrawerSessions`` keeps the newest in its ``DebugDrawerSessions/auditLog`` and publishes
/// each one through ``DebugDrawerSessions/auditEntries`` as it is recorded. It is `Codable`, so a
/// host can forward it as JSON:
///
/// ```json
/// {"capability":"MyApp.LogLevels","date":785000000,"event":{"commandApplied":{}},"sessionID":"…"}
/// ```
public struct DebugDrawerAuditEntry: Codable, Equatable, Sendable {
    /// What happened.
    public enum Event: Codable, Equatable, Sendable {
        /// A session opened, to expire at `expires`.
        case sessionOpened(expires: Date)
        /// The session ended, as `reason` says.
        case sessionEnded(Ending)
        /// A command was applied to the capability.
        case commandApplied
        /// A command was refused, as `reason` says, and changed nothing.
        case commandRefused(Refusal)
        /// A session-scoped change the capability made was reverted as its session ended.
        case changeReverted
    }

    /// Why a session ended.
    public enum Ending: String, Codable, Sendable {
        /// The sidecar or the host ended it.
        case ended
        /// It reached its expiry.
        case expired
    }

    /// Why a command was refused.
    public enum Refusal: String, Codable, Sendable {
        /// No session was open.
        case noActiveSession
        /// The capability's model was registered without a ``DebugDrawerChangeScope``, so what
        /// becomes of its changes when the session ends is unknown.
        case undeclaredScope
        /// No model is registered under the capability's ID.
        case unknownCapability
        /// The command didn't decode as one of the capability's commands.
        case malformedCommand
        /// A session was asked to open while one was open.
        case sessionAlreadyActive
        /// A session was asked to open for a duration that isn't a positive number.
        case invalidDuration
    }

    /// When it happened.
    public let date: Date
    /// The session it happened in, or `nil` for a command refused while none was open.
    public let sessionID: UUID?
    /// The capability: the ID the model was registered under, or ``DebugDrawerSessions/pluginID``
    /// for a session opening or ending.
    public let capability: String
    /// What happened.
    public let event: Event

    /// An entry.
    ///
    /// - Parameters:
    ///   - date: When it happened.
    ///   - sessionID: The session it happened in.
    ///   - capability: The capability it concerns.
    ///   - event: What happened.
    public init(date: Date, sessionID: UUID?, capability: String, event: Event) {
        self.date = date
        self.sessionID = sessionID
        self.capability = capability
        self.event = event
    }
}
