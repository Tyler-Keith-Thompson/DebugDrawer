import Combine
import Foundation
import os

// The sidecar's sessions: every command from outside the process acts within one. A
// `DebugDrawerModelRegistry` made with sessions (in a debug build), or a `DebugDrawerReceiver`
// (in any build), asks them before performing a command a transport carried in, and they refuse
// it unless a session is open and the host declared what becomes of the capability's changes;
// they record each outcome in the audit log, and revert the session-scoped changes as the
// session ends or expires.
//
// The sessions are a plugin model of their own, served by the registry under `pluginID`: a
// sidecar opens and ends a session with commands, and reads its state from snapshots, over
// whichever transport it already uses, so the wire needs no new message kinds and a sidecar of
// an older protocol version can open one too. The host reads the same state from `snapshot` and
// draws its own indicator, in its own style: the sessions are UI-less, as the release-build
// receiver must be (charter D6). They live in the receiver's module and are real in every build,
// as the receiver is; in a release build the drawer's registry and servers are stand-ins that
// never reach them, so only a receiver opens one there.
//
// Expiry is an event: a one-shot timer at the expiry date (`SessionTimer`), and, as a timer may
// fire late in an app that was suspended, a check against the clock before each command, so a
// command after the expiry date never lands. Rejected: polling the clock on a repeating timer
// (work while nothing happens), and extending an open session when asked to open another (a
// sidecar could keep one open past the host's maximum).
//
// The audit log is in memory and bounded: the newest `auditCapacity` entries, while
// `auditEntries` publishes every entry as it is recorded, for a host that forwards them (to its
// own log, a file, a server). Rejected: writing it to disk here (where and for how long is the
// host's policy, and the host may not want a file at all) and an unbounded array.
//
// Grants (charter D6) are optional: with a `DebugDrawerGrantPolicy`, a session opens only with a
// grant the policy admits, once per grant, lasting no longer than the grant, and every command in
// it must be to a capability the grant lists. The grant travels once, with `open`: the session is
// the unit a grant authorizes, its expiry already reverts what was changed, and the capabilities'
// own commands stay the model's vocabulary, untouched. Rejected: a grant with every command (every
// capability's wire format would need an envelope, and the token would cross the store again and
// again), and verifying in the receiver (a debug registry made with sessions would skip it).
// Single use is remembered in memory, for the grant's lifetime: a relaunched app forgets it, so a
// grant intercepted from the store could open one more session until it expires; keep grants
// short. Rejected: persisting used IDs (a file of the app's that outlives its purpose, in a
// container the attacker this guards against may write to).

/// The sidecar's sessions: commands from outside the process act only while one is open, it
/// expires, ending it reverts its session-scoped changes, and every command is audited.
///
/// Make a ``DebugDrawerReceiver`` with them, enable each capability with its
/// ``DebugDrawerChangeScope``, and show an indicator while ``snapshot`` is active:
///
/// ```swift
/// let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
/// let receiver = DebugDrawerReceiver(directory: storeDirectory, sessions: sessions)
/// receiver.enable(.model(logLevels, id: "MyApp.LogLevels", scope: .session(revertWith: .resetLevels)))
/// ```
///
/// In a debug build, a `DebugDrawerModelRegistry(sessions:)` gates the drawer's own servers with
/// them the same way.
///
/// A sidecar opens a session by connecting to ``pluginID`` with ``DebugDrawerSessionState``
/// snapshots and ``DebugDrawerSessionCommand`` commands, and sending
/// ``DebugDrawerSessionCommand/open(duration:grant:)``. The host can end the session itself with
/// ``end()``.
///
/// Made with a ``DebugDrawerGrantPolicy``, they open a session only with a valid grant, and apply
/// a command only to a capability the grant lists; see ``init(maximumDuration:auditCapacity:grantPolicy:)``.
///
/// They work in every build, as the receiver does. In a release build only a receiver opens one:
/// the drawer's registry and servers are stand-ins that never reach them.
@MainActor
public final class DebugDrawerSessions: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerReceiver", category: "DebugDrawerSessions")

    /// The ID a `DebugDrawerModelRegistry` made with sessions serves them under.
    public static let pluginID = "DebugDrawer.Sessions"
    /// How many entries ``auditLog`` keeps unless the host says otherwise.
    public static let defaultAuditCapacity = 1000

    /// Whether a session is open, and until when. Show an indicator while it is active.
    @Published public private(set) var snapshot = DebugDrawerSessionState.inactive
    /// The newest entries of the audit log, oldest first: at most ``auditCapacity``.
    @Published public private(set) var auditLog: [DebugDrawerAuditEntry] = []

    /// The longest a session lasts, in seconds; a session asked to last longer expires then.
    public let maximumDuration: TimeInterval
    /// The most entries ``auditLog`` keeps; older ones are dropped, after
    /// ``auditEntries`` published them.
    public let auditCapacity: Int
    /// What a grant must satisfy for a session to open with it, or `nil` when sessions open
    /// without one.
    public let grantPolicy: DebugDrawerGrantPolicy?

    private let clock: any SessionClock
    private let timer: any SessionTimer
    private let recorded = PassthroughSubject<DebugDrawerAuditEntry, Never>()
    /// What to put back as the open session ends, by capability, in the order each was first
    /// changed in it.
    private var reverts: [(capability: String, revert: @MainActor () -> Void)] = []
    /// The grants sessions opened with, by ID, until each expires: each opens one session.
    private var usedGrants: [String: Date] = [:]

    /// Sessions that last at most `maximumDuration` seconds.
    ///
    /// With a `grantPolicy`, a session opens only with a grant the policy admits (the right
    /// audience, valid now, never used before), expires no later than the grant, and applies a
    /// command only to a capability the grant lists; everything else is refused and audited.
    /// Without one, sessions open as the sidecar asks.
    ///
    /// - Parameters:
    ///   - maximumDuration: The longest a session lasts, in seconds. A session opens only
    ///     for a positive duration, so a maximum that isn't positive opens none.
    ///   - auditCapacity: The most entries ``auditLog`` keeps; none when it isn't positive.
    ///     ``auditEntries`` publishes every entry either way.
    ///   - grantPolicy: What a grant must satisfy, or `nil` for sessions without grants.
    public convenience init(
        maximumDuration: TimeInterval,
        auditCapacity: Int = DebugDrawerSessions.defaultAuditCapacity,
        grantPolicy: DebugDrawerGrantPolicy? = nil
    ) {
        self.init(
            maximumDuration: maximumDuration, auditCapacity: auditCapacity, grantPolicy: grantPolicy,
            clock: _SessionClock(), timer: RunLoopSessionTimer()
        )
    }

    /// Sessions on `clock`, expiring by `timer`.
    init(
        maximumDuration: TimeInterval,
        auditCapacity: Int,
        grantPolicy: DebugDrawerGrantPolicy? = nil,
        clock: any SessionClock,
        timer: any SessionTimer
    ) {
        self.maximumDuration = maximumDuration
        self.auditCapacity = auditCapacity
        self.grantPolicy = grantPolicy
        self.clock = clock
        self.timer = timer
    }

    /// Every audit entry as it is recorded, for a host that forwards them; ``auditLog`` keeps
    /// only the newest.
    public var auditEntries: AnyPublisher<DebugDrawerAuditEntry, Never> {
        recorded.eraseToAnyPublisher()
    }

    /// Opens or ends a session, as a sidecar asks.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: DebugDrawerSessionCommand) {
        switch command {
        case let .open(duration, grant): open(for: duration, grant: grant)
        case .end: finish(.ended)
        }
    }

    /// Ends the open session, reverting its session-scoped changes; does nothing when none is
    /// open. For a host that lets the person holding the device end it.
    public func end() {
        finish(.ended)
    }

    /// Performs a command to `capability`, through `perform`, if a session is open and the
    /// capability's scope is declared, and records what came of it.
    ///
    /// - Parameters:
    ///   - capability: The ID the capability's model was registered under.
    ///   - scope: What becomes of its changes as the session ends; `nil` when undeclared.
    ///   - perform: Performs the command; `false` when it didn't decode.
    package func apply(to capability: String, scope: CapabilityScope?, _ perform: () -> Bool) {
        apply(to: capability, scope: scope, requiresGrant: false) { perform() ? nil : .malformedCommand }
    }

    /// Performs a command to `capability`, through `perform`, if a session is open, its grant
    /// (when it needs one) covers the capability, and the capability's scope is declared, and
    /// records what came of it.
    ///
    /// - Parameters:
    ///   - capability: The ID the capability's model was registered under.
    ///   - scope: What becomes of its changes as the session ends; `nil` when undeclared.
    ///   - requiresGrant: Whether the capability needs a grant listing it even when the sessions
    ///     have no ``grantPolicy``.
    ///   - perform: Performs the command, or returns why it was refused, having changed nothing.
    package func apply(
        to capability: String,
        scope: CapabilityScope?,
        requiresGrant: Bool,
        _ perform: () -> DebugDrawerAuditEntry.Refusal?
    ) {
        expireIfDue()
        guard let session = snapshot.session else {
            refuse(capability, .noActiveSession)
            return
        }
        if grantPolicy != nil || requiresGrant {
            guard let grant = session.grant else {
                refuse(capability, .grantMissing)
                return
            }
            guard grant.capabilities.contains(capability) else {
                refuse(capability, .capabilityNotGranted)
                return
            }
        }
        guard let scope else {
            refuse(capability, .undeclaredScope)
            return
        }
        if let reason = perform() {
            refuse(capability, reason)
            return
        }
        if case let .session(revert) = scope, !reverts.contains(where: { $0.capability == capability }) {
            reverts.append((capability, revert))
        }
        record(capability, .commandApplied, in: session.id)
    }

    /// Ends the open session as `ending` says, reverting its session-scoped changes; does nothing
    /// when none is open. For a receiver whose host turned it off (``DebugDrawerAuditEntry/Ending/disabledByHost``).
    package func end(because ending: DebugDrawerAuditEntry.Ending) {
        finish(ending)
    }

    /// Reverts `capability`'s session-scoped change in the open session now, rather than as the
    /// session ends, and records it; does nothing when none is open or the capability changed
    /// nothing in it. A later command applied to it in the same session is reverted as the
    /// session ends, as usual.
    package func revertChanges(of capability: String) {
        guard let session = snapshot.session, let index = reverts.firstIndex(where: { $0.capability == capability }) else { return }
        let revert = reverts.remove(at: index).revert
        revert()
        record(capability, .changeReverted, in: session.id)
    }

    /// Records that a command to `capability` was refused for `reason`.
    package func refuse(_ capability: String, _ reason: DebugDrawerAuditEntry.Refusal) {
        Self.logger.notice("Refused a command for \(capability, privacy: .public): \(reason.rawValue, privacy: .public)")
        record(capability, .commandRefused(reason), in: snapshot.session?.id)
    }

    private func open(for duration: TimeInterval, grant token: String?) {
        expireIfDue()
        guard !snapshot.isActive else {
            refuse(Self.pluginID, .sessionAlreadyActive)
            return
        }
        let now = clock.now
        var grant: DebugDrawerGrant?
        if let grantPolicy {
            switch grantPolicy.admit(token, at: now) {
            case let .refused(reason):
                refuse(Self.pluginID, reason)
                return
            case let .admitted(admitted):
                usedGrants = usedGrants.filter { $0.value > now }
                guard usedGrants[admitted.id] == nil else {
                    refuse(Self.pluginID, .grantReplayed)
                    return
                }
                grant = admitted
            }
        }
        // The policy admits a grant only before its expiry, so its bound is positive.
        let duration = min(duration, maximumDuration, grant.map { $0.expires.timeIntervalSince(now) } ?? .infinity)
        guard duration > 0 else {
            // NaN fails this comparison too.
            refuse(Self.pluginID, .invalidDuration)
            return
        }
        if let grant {
            // Used only once the session opens, so a refused open doesn't spend the grant.
            usedGrants[grant.id] = grant.expires
        }
        let session = DebugDrawerSession(id: UUID(), opened: now, expires: now.addingTimeInterval(duration), grant: grant)
        snapshot = .active(session)
        timer.schedule(at: session.expires) { [weak self] in
            guard self?.snapshot.session?.id == session.id else { return }
            self?.finish(.expired)
        }
        let reference = grant.map { DebugDrawerAuditEntry.GrantReference(id: $0.id, subject: $0.subject) }
        record(Self.pluginID, .sessionOpened(expires: session.expires, grant: reference), in: session.id)
    }

    /// Ends the open session, if any, reverting its session-scoped changes first.
    private func finish(_ ending: DebugDrawerAuditEntry.Ending) {
        guard let session = snapshot.session else { return }
        timer.cancel()
        let owed = reverts
        reverts = []
        for (capability, revert) in owed {
            revert()
            record(capability, .changeReverted, in: session.id)
        }
        snapshot = .inactive
        record(Self.pluginID, .sessionEnded(ending), in: session.id)
    }

    /// Expires the open session if its expiry has passed and the timer hasn't fired yet, as
    /// it may not have in an app that was suspended.
    private func expireIfDue() {
        guard let session = snapshot.session, clock.now >= session.expires else { return }
        finish(.expired)
    }

    private func record(_ capability: String, _ event: DebugDrawerAuditEntry.Event, in sessionID: UUID?) {
        let entry = DebugDrawerAuditEntry(date: clock.now, sessionID: sessionID, capability: capability, event: event)
        auditLog = Array((auditLog + [entry]).suffix(max(auditCapacity, 0)))
        recorded.send(entry)
    }
}

extension DebugDrawerSessions {
    /// A capability's ``DebugDrawerChangeScope``, its model's type erased.
    package enum CapabilityScope {
        /// Its changes last for the session, and `revert` puts them back.
        case session(revert: @MainActor () -> Void)
        /// Its changes outlive the session.
        case persistent

        @MainActor
        package init<Model: DebugDrawerPluginModel>(_ scope: DebugDrawerChangeScope<Model>, of model: Model) {
            switch scope.kind {
            case let .session(command): self = .session { model.perform(command) }
            case .persistent: self = .persistent
            }
        }
    }
}
