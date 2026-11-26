import Combine
import Foundation
import os

// Keeps a backgrounded app reachable by its sidecar for as long as a session is open, through only
// what the platform sanctions (charter D10, `_BackgroundExecution`), and lets go as the session
// ends. It observes `DebugDrawerSessions`' published state rather than living inside the sessions:
// the sessions decide what a command may do, the keeper only how long the app keeps running, so a
// host that wants none (a Mac app that doesn't nap, a test) leaves it out.
//
// It lives in the receiver and is real in every build, like the sessions it follows: a release
// build's receiver keeps its app reachable the same way, and only while a session is open, which
// the receiver allows only for the capabilities the host enables. Rejected: a debug-only keeper in
// core with a release stand-in (the production receiver, the app D10 is about, would get none); a
// module of its own (charter N4's shared targets).
//
// Two requests, by who asked:
// - A session the sidecar opened gets the short one the platform has (a UIKit background task, a
//   `ProcessInfo` activity) from the moment it opens, so a switch to the sidecar has its handoff
//   time, and again each time the app returns to the foreground after the system ended it.
// - A session the person holding the device starts (`startSession`, from a button) also submits a
//   `BGContinuedProcessingTask` on iOS 26 and later, which only a person's action in the foreground
//   may start: the system shows its progress and a way to stop it, which is the platform's own
//   indicator. Its identifier is the host's prefix (listed as `<prefix>.*` in
//   `BGTaskSchedulerPermittedIdentifiers`) and the session's ID, so each is registered once, as
//   the scheduler demands. The short request stays until the task runs, so the app isn't left
//   without either; where the task is refused or unavailable, the short request is what the
//   session gets.
//
// Every request ends as the session ends or expires. The session ends as the last sidecar
// disconnects, for a keeper told so (core's socket server, through the
// `init(sessions:socketServer:continuedProcessingIdentifierPrefix:)` core adds, as its server is
// debug-only): nothing should keep the app running for a sidecar that is gone, and a session nobody
// drives shouldn't hold its changes until expiry. While the continued task runs it reports the
// session's elapsed seconds of its length as its progress, every second (`ProgressTimer`) and at
// each audit entry. The system expires a continued processing task whose progress stops moving and
// shows it as failed, and on an iPhone it did so within a minute when progress moved only with the
// sidecar's commands: a session the person is reading in the sidecar sends none for a while.
//
// Rejected: progress only from the sidecar's commands (the system expired the idle session's task
// as stalled); queueing the
// continued task (`.queue`) when the system can't run it at once (it would keep nothing running
// now, and could start long after the session ended); claiming a background mode, audio, location
// or VoIP, to stay alive (charter D10); keeping the request after the sidecar disconnects until
// the session expires (the app would run for nobody).

/// Keeps the app running in the background while a sidecar's session is open, so the sidecar
/// stays connected, and lets go as the session ends.
///
/// Make one with the sessions, and hold it as long as they live; a debug build that serves the
/// socket passes its socket server too, so the session ends as the sidecar disconnects:
///
/// ```swift
/// let keeper = DebugDrawerBackgroundKeeper(sessions: sessions)
/// ```
///
/// While a session is open it holds what the platform sanctions: a UIKit background task on
/// iOS, iPadOS, tvOS and visionOS (a short handoff), a `ProcessInfo` activity against App Nap on
/// macOS and Mac Catalyst, and nothing on watchOS. From a person's action,
/// ``startSession(duration:title:subtitle:)`` opens a session and, on iOS and iPadOS 26 and
/// later, a `BGContinuedProcessingTask` whose progress the system shows for the session's
/// length. Every request ends as the session ends or expires. ``request`` says what is held.
///
/// It works in every build, as the receiver and its sessions do.
@MainActor
public final class DebugDrawerBackgroundKeeper: ObservableObject {
    private static let logger = Logger(subsystem: "DebugDrawer", category: "DebugDrawerBackgroundKeeper")
    /// Seconds between progress reports while the continued task runs: the progress counts
    /// seconds, so each report moves it on.
    private static let progressInterval: TimeInterval = 1

    /// The identifier prefix of the continued processing task unless the host passes another:
    /// the app's bundle identifier and `.DebugDrawerSession`, so the app's Info.plist lists
    /// `$(PRODUCT_BUNDLE_IDENTIFIER).DebugDrawerSession.*` in `BGTaskSchedulerPermittedIdentifiers`.
    /// `nil` in a process with no bundle identifier.
    public static var defaultContinuedProcessingPrefix: String? {
        Bundle.main.bundleIdentifier.map { "\($0).DebugDrawerSession" }
    }

    /// What the keeper holds now.
    @Published public private(set) var request = DebugDrawerBackgroundRequest.none

    /// The sessions whose state it follows.
    public let sessions: DebugDrawerSessions
    /// The continued processing task's identifier prefix; `nil` asks for none.
    public let continuedProcessingIdentifierPrefix: String?

    private let execution: any BackgroundExecution
    private let clock: any SessionClock
    private let progressTimer: any ProgressTimer
    private var shortRequest: (any BackgroundExecutionRequest)?
    private var continued: Continued?
    private var subscriptions: Set<AnyCancellable> = []

    /// A keeper of the app while `sessions` has one open.
    ///
    /// - Parameters:
    ///   - sessions: The sessions whose state it follows.
    ///   - continuedProcessingIdentifierPrefix: The prefix of the continued processing task's
    ///     identifier, listed as `<prefix>.*` in the app's `BGTaskSchedulerPermittedIdentifiers`;
    ///     `nil` asks for no continued processing task.
    public convenience init(
        sessions: DebugDrawerSessions,
        continuedProcessingIdentifierPrefix: String? = DebugDrawerBackgroundKeeper.defaultContinuedProcessingPrefix
    ) {
        self.init(sessions: sessions, sidecarDisconnections: nil, continuedProcessingIdentifierPrefix: continuedProcessingIdentifierPrefix)
    }

    /// A keeper that also ends the session each time `sidecarDisconnections` publishes, as the last
    /// sidecar disconnects; core's socket server overload calls it.
    package convenience init(
        sessions: DebugDrawerSessions,
        sidecarDisconnections: AnyPublisher<Void, Never>?,
        continuedProcessingIdentifierPrefix: String?
    ) {
        self.init(
            sessions: sessions,
            sidecarDisconnections: sidecarDisconnections,
            continuedProcessingIdentifierPrefix: continuedProcessingIdentifierPrefix,
            execution: _BackgroundExecution(),
            clock: _SessionClock(),
            progressTimer: RunLoopProgressTimer()
        )
    }

    /// A keeper asking `execution` for its requests, timing progress by `clock` and reporting it
    /// at each of `progressTimer`'s ticks.
    init(
        sessions: DebugDrawerSessions,
        sidecarDisconnections: AnyPublisher<Void, Never>?,
        continuedProcessingIdentifierPrefix: String?,
        execution: any BackgroundExecution,
        clock: any SessionClock,
        progressTimer: any ProgressTimer
    ) {
        self.sessions = sessions
        self.continuedProcessingIdentifierPrefix = continuedProcessingIdentifierPrefix
        self.execution = execution
        self.clock = clock
        self.progressTimer = progressTimer
        sessions.$snapshot
            .map(\.isActive)
            .removeDuplicates()
            .sink { [weak self] isActive in
                MainActor.assumeIsolated { self?.sessionChanged(isActive: isActive) }
            }
            .store(in: &subscriptions)
        execution.foregroundEntries
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.cameToForeground() }
            }
            .store(in: &subscriptions)
        sessions.auditEntries
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.reportProgress() }
            }
            .store(in: &subscriptions)
        sidecarDisconnections?
            .sink { [weak self] in
                MainActor.assumeIsolated { self?.sidecarDisconnected() }
            }
            .store(in: &subscriptions)
    }

    /// Opens a session, unless one is open, and keeps the app running for it: call it from a
    /// person's action, such as a Start Debug Session button, before they switch to the
    /// sidecar.
    ///
    /// On iOS and iPadOS 26 and later, with a ``continuedProcessingIdentifierPrefix`` the
    /// app's Info.plist permits, it submits a `BGContinuedProcessingTask`: the system shows
    /// `title`, `subtitle` and the session's progress until the session ends, and the person
    /// can stop it there, which ends the session. Elsewhere, or when the system refuses the
    /// task, the session keeps the platform's short request. Does nothing more while a task is
    /// already submitted for the open session.
    ///
    /// - Parameters:
    ///   - duration: How long the session lasts, in seconds, at most the sessions'
    ///     ``DebugDrawerSessions/maximumDuration``. Ignored when a session is open.
    ///   - title: What the system's progress shows as its title, such as "Debug session".
    ///   - subtitle: What it shows beneath, such as the sidecar's name.
    public func startSession(duration: TimeInterval, title: String, subtitle: String) {
        if !sessions.snapshot.isActive {
            sessions.perform(.open(duration: duration))
        }
        guard let session = sessions.snapshot.session, continued == nil, let continuedProcessingIdentifierPrefix else { return }
        let identifier = "\(continuedProcessingIdentifierPrefix).\(session.id.uuidString)"
        continued = .submitted(identifier: identifier)
        let execution = execution
        Task { [weak self] in
            do throws(ContinuedProcessingRefusal) {
                try await execution.submitContinuedProcessing(
                    identifier: identifier, title: title, subtitle: subtitle,
                    launched: { [weak self] task in self?.launched(task, identifier: identifier) },
                    expired: { [weak self] in self?.continuedExpired(identifier: identifier) }
                )
            } catch {
                self?.submissionFailed(identifier: identifier, error)
            }
        }
    }

    private func sessionChanged(isActive: Bool) {
        if isActive {
            beginShortRequest()
        } else {
            release()
        }
    }

    private func cameToForeground() {
        guard sessions.snapshot.isActive else { return }
        beginShortRequest()
    }

    /// Begins the platform's short request, unless one, or a continued task, is held.
    private func beginShortRequest() {
        guard shortRequest == nil, continued?.task == nil else { return }
        shortRequest = execution.begin(reason: "DebugDrawer sidecar session") { [weak self] in
            self?.shortRequestExpired()
        }
        publish()
    }

    private func shortRequestExpired() {
        Self.logger.notice("The system ended the sidecar session's background task")
        shortRequest = nil
        publish()
    }

    private func launched(_ task: any ContinuedProcessingTask, identifier: String) {
        guard continued == .submitted(identifier: identifier), sessions.snapshot.isActive else {
            task.complete()
            return
        }
        continued = .running(identifier: identifier, task)
        shortRequest?.end()
        shortRequest = nil
        reportProgress()
        progressTimer.start(every: Self.progressInterval) { [weak self] in self?.reportProgress() }
        publish()
    }

    private func submissionFailed(identifier: String, _ error: ContinuedProcessingRefusal) {
        guard continued == .submitted(identifier: identifier) else { return }
        Self.logger.notice("No continued processing task for the session: \(String(describing: error), privacy: .public)")
        continued = nil
        publish()
    }

    /// The person stopped the task, or the system needed its resources: either way nothing
    /// keeps the app running for the session any more, so it ends.
    private func continuedExpired(identifier: String) {
        guard case .running(identifier, _)? = continued else { return }
        Self.logger.notice("The continued processing task ended before the session")
        progressTimer.stop()
        continued = nil
        publish()
        sessions.end()
    }

    private func sidecarDisconnected() {
        guard sessions.snapshot.isActive else { return }
        Self.logger.info("The sidecar disconnected; ending its session")
        sessions.end()
    }

    /// Shows the session's elapsed seconds of its length in the continued task's progress.
    private func reportProgress() {
        guard let task = continued?.task, let session = sessions.snapshot.session else { return }
        let total = max(Int64(session.expires.timeIntervalSince(session.opened).rounded()), 1)
        let elapsed = Int64(clock.now.timeIntervalSince(session.opened).rounded())
        task.report(completed: min(max(elapsed, 0), total), of: total)
    }

    /// Ends every request.
    private func release() {
        progressTimer.stop()
        shortRequest?.end()
        shortRequest = nil
        switch continued {
        case let .submitted(identifier)?: execution.cancelContinuedProcessing(identifier: identifier)
        case let .running(_, task)?: task.complete()
        case nil: break
        }
        continued = nil
        publish()
    }

    private func publish() {
        let held: DebugDrawerBackgroundRequest =
            if continued?.task != nil {
                .continuedProcessing
            } else if shortRequest != nil {
                execution.shortRequest
            } else {
                .none
            }
        if request != held {
            request = held
        }
    }
}

extension DebugDrawerBackgroundKeeper {
    /// The continued processing task, from submission until the session ends.
    private enum Continued: Equatable {
        /// Submitted under `identifier`, not yet run.
        case submitted(identifier: String)
        /// Running, its progress shown.
        case running(identifier: String, any ContinuedProcessingTask)

        /// The running task, or `nil` while it waits.
        var task: (any ContinuedProcessingTask)? {
            switch self {
            case .submitted: nil
            case let .running(_, task): task
            }
        }

        nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
            switch (lhs, rhs) {
            case let (.submitted(left), .submitted(right)): left == right
            case let (.running(left, leftTask), .running(right, rightTask)): left == right && leftTask === rightTask
            default: false
            }
        }
    }
}
