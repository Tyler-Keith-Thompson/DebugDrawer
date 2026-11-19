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
/// ``DebugDrawerSessionCommand/open(duration:)``. The host can end the session itself with
/// ``end()``.
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

    private let clock: any SessionClock
    private let timer: any SessionTimer
    private let recorded = PassthroughSubject<DebugDrawerAuditEntry, Never>()
    /// What to put back as the open session ends, by capability, in the order each was first
    /// changed in it.
    private var reverts: [(capability: String, revert: @MainActor () -> Void)] = []

    /// Sessions that last at most `maximumDuration` seconds.
    ///
    /// - Parameters:
    ///   - maximumDuration: The longest a session lasts, in seconds. A session opens only
    ///     for a positive duration, so a maximum that isn't positive opens none.
    ///   - auditCapacity: The most entries ``auditLog`` keeps; none when it isn't positive.
    ///     ``auditEntries`` publishes every entry either way.
    public convenience init(maximumDuration: TimeInterval, auditCapacity: Int = DebugDrawerSessions.defaultAuditCapacity) {
        self.init(maximumDuration: maximumDuration, auditCapacity: auditCapacity, clock: _SessionClock(), timer: RunLoopSessionTimer())
    }

    /// Sessions on `clock`, expiring by `timer`.
    init(maximumDuration: TimeInterval, auditCapacity: Int, clock: any SessionClock, timer: any SessionTimer) {
        self.maximumDuration = maximumDuration
        self.auditCapacity = auditCapacity
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
        case let .open(duration): open(for: duration)
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
        expireIfDue()
        guard let session = snapshot.session else {
            refuse(capability, .noActiveSession)
            return
        }
        guard let scope else {
            refuse(capability, .undeclaredScope)
            return
        }
        guard perform() else {
            refuse(capability, .malformedCommand)
            return
        }
        if case let .session(revert) = scope, !reverts.contains(where: { $0.capability == capability }) {
            reverts.append((capability, revert))
        }
        record(capability, .commandApplied, in: session.id)
    }

    /// Records that a command to `capability` was refused for `reason`.
    package func refuse(_ capability: String, _ reason: DebugDrawerAuditEntry.Refusal) {
        Self.logger.notice("Refused a command for \(capability, privacy: .public): \(reason.rawValue, privacy: .public)")
        record(capability, .commandRefused(reason), in: snapshot.session?.id)
    }

    private func open(for duration: TimeInterval) {
        expireIfDue()
        guard !snapshot.isActive else {
            refuse(Self.pluginID, .sessionAlreadyActive)
            return
        }
        let duration = min(duration, maximumDuration)
        guard duration > 0 else {
            // NaN fails this comparison too.
            refuse(Self.pluginID, .invalidDuration)
            return
        }
        let now = clock.now
        let session = DebugDrawerSession(id: UUID(), opened: now, expires: now.addingTimeInterval(duration))
        snapshot = .active(session)
        timer.schedule(at: session.expires) { [weak self] in
            guard self?.snapshot.session?.id == session.id else { return }
            self?.finish(.expired)
        }
        record(Self.pluginID, .sessionOpened(expires: session.expires), in: session.id)
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
