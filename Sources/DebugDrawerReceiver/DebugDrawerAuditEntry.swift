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
        /// A session opened, to expire at `expires`, with the grant `grant` names, if any.
        case sessionOpened(expires: Date, grant: GrantReference? = nil)
        /// The session ended, as `reason` says.
        case sessionEnded(Ending)
        /// A command was applied to the capability.
        case commandApplied
        /// A command was refused, as `reason` says, and changed nothing.
        case commandRefused(Refusal)
        /// A session-scoped change the capability made was reverted as its session ended.
        case changeReverted
    }

    /// The grant a session opened with, named but never copied: its ID and who holds it, never
    /// the token or its signature.
    public struct GrantReference: Codable, Equatable, Sendable {
        /// The grant's ``DebugDrawerGrant/id``.
        public let id: String
        /// Who holds it: the grant's ``DebugDrawerGrant/subject``.
        public let subject: String

        /// A reference to a grant.
        ///
        /// - Parameters:
        ///   - id: The grant's ID.
        ///   - subject: Who holds it.
        public init(id: String, subject: String) {
            self.id = id
            self.subject = subject
        }
    }

    /// Why a session ended.
    public enum Ending: String, Codable, Sendable {
        /// The sidecar or the host ended it.
        case ended
        /// It reached its expiry.
        case expired
        /// The host turned the receiver off while it was open: its gate,
        /// ``DebugDrawerReceiver/isAllowed``, returned `false` at a command, at
        /// ``DebugDrawerReceiver/reevaluateGates()`` or as the app came to the foreground.
        case disabledByHost
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
        /// The command didn't decode as one of the capability's commands, or carried a value the
        /// capability doesn't take.
        case malformedCommand
        /// The command named something the capability doesn't expose to a sidecar, such as a
        /// tweak the host didn't mark production-safe.
        case notExposed
        /// A session was asked to open while one was open.
        case sessionAlreadyActive
        /// A session was asked to open for a duration that isn't a positive number.
        case invalidDuration
        /// The sessions have a ``DebugDrawerGrantPolicy`` and a session was asked to open without
        /// a grant; or a capability that requires a grant was sent a command in a session that
        /// has none.
        case grantMissing
        /// The grant's verifier rejected it: it is malformed, or no trusted key signed it as it
        /// is.
        case grantInvalid
        /// The grant was issued for another app: the policy's audience isn't among its
        /// audiences.
        case grantWrongAudience
        /// The grant isn't valid yet, even allowing for the policy's clock-skew tolerance.
        case grantNotYetValid
        /// The grant has expired.
        case grantExpired
        /// A session already opened with the grant: each opens one session at most.
        case grantReplayed
        /// The session's grant doesn't list the capability the command was for.
        case capabilityNotGranted
        /// The host turned the receiver off: its gate, ``DebugDrawerReceiver/isAllowed``, returned
        /// `false`. Checked before anything else, a session's opening included.
        case receiverDisabled
        /// The host turned this capability off: the gate it was enabled with,
        /// ``DebugDrawerReceiver/enable(_:isAllowed:)``, returned `false`.
        case capabilityDisabled
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
