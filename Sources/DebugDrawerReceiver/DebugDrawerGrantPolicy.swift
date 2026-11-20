import Foundation

// The checks every grant passes, whatever its format: the verifier authenticates and reads it,
// and this decides whether it admits a session now. The clock-skew tolerance applies to
// `notBefore` only: a server whose clock runs ahead of the device's issues grants that would
// otherwise be refused as not yet valid for their first seconds, while widening the other end
// would only let a grant outlive what its issuer allowed. Rejected: a tolerance on both ends, as
// JWT libraries often apply (it extends every grant), and none (a fresh grant from a server a few
// seconds ahead fails).

/// What a grant must satisfy before a sidecar's session opens with it: a verifier that
/// authenticates it, the app it must be issued for, and how far the issuer's clock may run ahead
/// of the device's.
///
/// Give it to ``DebugDrawerSessions/init(maximumDuration:auditCapacity:grantPolicy:)`` and every
/// session needs a valid grant, and every command a grant that covers its capability:
///
/// ```swift
/// let sessions = DebugDrawerSessions(maximumDuration: 15 * 60, grantPolicy: DebugDrawerGrantPolicy(
///     verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey)]),
///     audience: "com.example.MyApp"
/// ))
/// ```
public struct DebugDrawerGrantPolicy: Sendable {
    /// How far ahead of the device's clock, in seconds, a grant's issuer may be, unless the host
    /// says otherwise: a minute.
    public static let defaultClockSkewTolerance: TimeInterval = 60

    /// Authenticates each grant and reads it.
    public let verifier: any DebugDrawerGrantVerifier
    /// The app a grant must be issued for: one of its ``DebugDrawerGrant/audiences``. Usually the
    /// app's bundle identifier.
    public let audience: String
    /// How many seconds before its ``DebugDrawerGrant/notBefore`` a grant is already accepted.
    public let clockSkewTolerance: TimeInterval

    /// A policy.
    ///
    /// - Parameters:
    ///   - verifier: Authenticates each grant and reads it.
    ///   - audience: The app a grant must be issued for, usually its bundle identifier.
    ///   - clockSkewTolerance: How many seconds before its start a grant is already accepted; one
    ///     that is negative or not a number counts as none.
    public init(
        verifier: any DebugDrawerGrantVerifier,
        audience: String,
        clockSkewTolerance: TimeInterval = DebugDrawerGrantPolicy.defaultClockSkewTolerance
    ) {
        self.verifier = verifier
        self.audience = audience
        // NaN fails this comparison, so it counts as none too.
        self.clockSkewTolerance = clockSkewTolerance > 0 ? clockSkewTolerance : 0
    }

    /// The grant `token` carries, if it admits a session at `now`, or why not. Whether it was
    /// used before is the sessions' to check.
    func admit(_ token: String?, at now: Date) -> Admission {
        guard let token else { return .refused(.grantMissing) }
        let grant: DebugDrawerGrant
        do {
            grant = try verifier.verify(token)
        } catch {
            return .refused(.grantInvalid)
        }
        guard grant.audiences.contains(audience) else { return .refused(.grantWrongAudience) }
        guard now >= grant.notBefore.addingTimeInterval(-clockSkewTolerance) else { return .refused(.grantNotYetValid) }
        guard now < grant.expires else { return .refused(.grantExpired) }
        return .admitted(grant)
    }

    /// Whether a grant admits a session.
    enum Admission {
        /// It does.
        case admitted(DebugDrawerGrant)
        /// It doesn't, for this reason.
        case refused(DebugDrawerAuditEntry.Refusal)
    }
}
