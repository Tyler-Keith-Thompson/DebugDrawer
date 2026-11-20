import Combine
import CoreFoundation
import DebugDrawerReceiver
import Foundation
import os

// The performance traces capability's model (DD-125, the charter's D9). It lives with the Hang
// Detector plugin's monitor, which it runs in release builds, rather than in the receiver: the
// receiver knows models, not plugins, and a host that records no traces links none of this.
//
// Started by the sidecar, not by the session: a session opened only to override a flag shouldn't
// put an observer on the app's main run loop and a watcher thread beside it. A `start` in a session
// makes the monitor and opens the signpost inbox; `stop` (the session's revert, so also its end,
// expiry and either gate turning off) stops the monitor (its observers removed, its watcher thread
// joined) and closes the inbox, so nothing runs while nothing records. Rejected: recording from the
// moment any session opens (overhead nobody asked for), and a monitor made at startup and only
// muted outside a session (its thread and observers would run in every customer's app).
//
// Signposts are the host's own calls (`beginInterval`/`endInterval`, shaped as `OSSignposter`'s),
// not read back from the system: `OSLogStore` gives an app its own log entries without an
// entitlement, but signposts reach the store only while a tool such as Instruments streams them,
// and reading the store is costly work on a timer, so a sidecar would see nothing on a customer's
// device. Nothing intercepts the app's own `os_signpost` calls. The interval's name is a
// `StaticString`, so what crosses to the sidecar is a literal from the app's code, never a value
// from its data.
//
// Where the data is: in memory, and in the capability's snapshot file in the app's own directory of
// the group's store, which the receiver writes and the sidecar reads; nowhere else, as with the
// diagnostics capture. Deleting the recording is emptying the snapshot and removing that file: the
// model does both as it stops, and removes the file as the receiver enables it, which deletes what a
// launch killed during a session left behind. A sidecar's export is its own copy, in its report.

/// The main thread's hitches and hangs, each with the stack it was stuck on, and the signpost
/// intervals the host marks, recorded while a sidecar records in its session, for a production
/// build.
///
/// The app makes it with the receiver's sessions, enables the capability, and marks the
/// intervals it wants timed:
///
/// ```swift
/// let traces = PerformanceTraces(sessions: sessions)
/// receiver.enable(.performanceTraces(traces))
///
/// let interval = traces.beginInterval("Load feed")
/// let feed = try await api.feed()
/// traces.endInterval(interval)
/// ```
///
/// Nothing runs until a sidecar, in an open session, sends ``Command/start``: then an observer
/// on the main run loop and a watcher thread record each stall of the main thread at least
/// ``hitchThreshold`` long, a hang from ``hangThreshold``, with the main thread's stack, and the
/// intervals that end. It stops, removing the observer and ending the thread, and deletes what it
/// recorded, as the sidecar sends ``Command/stop``, as the session ends or expires, or as a gate
/// turns it off. Outside a recording, ``beginInterval(_:)`` and ``endInterval(_:)`` record
/// nothing.
///
/// ## Overhead while recording
///
/// Measured by `PerformanceTracesOverheadTests` in an optimized build (`just test-release`) on an
/// Apple M1 Ultra, with the default thresholds. Outside a recording none of this runs; a signpost
/// call then costs about 0.06 µs.
///
/// - Main thread, every turn of its run loop: the observer reads the clock and takes an
///   uncontended lock at each checkpoint, about 0.13 µs each, about 0.6 µs a turn in all.
/// - Watcher thread: wakes every quarter of the hitch threshold, 40 times a second, for about
///   0.08 µs of work each besides the kernel's wake: about 3 µs of CPU a second.
/// - Each stall: the main thread is stopped once while its stack is read (a few µs), and once it
///   runs again its frames are named on the main actor, about 15 µs a frame (at most 128, so at
///   most about 2 ms a stall).
/// - Each signpost interval: about 0.45 µs to begin and end.
@MainActor
public final class PerformanceTraces: DebugDrawerPluginModel {
    private static let logger = Logger(subsystem: "DebugDrawerHangDetector", category: "PerformanceTraces")

    /// The ID the receiver serves it under.
    public nonisolated static let pluginID = "DebugDrawer.PerformanceTraces"
    /// The shortest stall recorded unless the host picks another: a tenth of a second, the
    /// shortest stall Instruments reports as a microhang.
    public nonisolated static let defaultHitchThreshold: Duration = .milliseconds(100)
    /// The shortest stall recorded as a hang unless the host picks another: a quarter of a second,
    /// the shortest stall Apple counts as a hang.
    public nonisolated static let defaultHangThreshold: Duration = .milliseconds(250)

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Starts recording in the open session, empty; does nothing while it records already.
        case start
        /// Stops recording and deletes everything recorded; what the session's end performs.
        case stop
        /// Records that the sidecar took a copy of the recording into its report, with how much it
        /// held; does nothing while it isn't recording.
        case export
    }

    /// An interval begun with ``beginInterval(_:)``, which ``endInterval(_:)`` ends; it records
    /// nothing when it began outside a recording.
    public struct IntervalState: Sendable {
        let name: StaticString
        let recording: SignpostRecording?
    }

    /// The recording now: empty while nothing records.
    @Published public private(set) var snapshot: Snapshot

    /// The shortest stall recorded.
    public let hitchThreshold: Duration
    /// The shortest stall recorded as a hang.
    public let hangThreshold: Duration

    /// The bounds the recording keeps to.
    public nonisolated var limits: Limits {
        inbox.limits
    }

    /// Watches the main thread while a sidecar records; `nil` otherwise.
    package private(set) var monitor: HangMonitor?

    private nonisolated let inbox: SignpostInbox
    private let now: @Sendable () -> Date
    /// The thread to watch and its sampler, asked as each recording starts.
    private let watchedThread: @MainActor () -> (runLoop: CFRunLoop, sampler: any StackSampler)
    /// The session open now, as the sessions last said.
    private var openSession: DebugDrawerSession?
    /// Where the receiver writes the snapshot, once one enabled the capability.
    private var snapshotFile: URL?
    private var sessionObservation: AnyCancellable?

    /// A recorder of the main thread's stalls and the host's signpost intervals, within
    /// `sessions`' sessions, as a sidecar starts it.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions.
    ///   - hitchThreshold: The shortest stall recorded; ``defaultHitchThreshold`` unless given.
    ///   - hangThreshold: The shortest stall recorded as a hang; ``defaultHangThreshold`` unless
    ///     given.
    ///   - limits: The bounds of one session's recording; ``Limits/standard`` unless given.
    /// - Precondition: `hitchThreshold` is positive and no longer than `hangThreshold`.
    public convenience init(
        sessions: DebugDrawerSessions,
        hitchThreshold: Duration = defaultHitchThreshold,
        hangThreshold: Duration = defaultHangThreshold,
        limits: Limits = .standard
    ) {
        // Dates read from the continuous clock, counted from one wall-clock reading, so an
        // interval's duration doesn't jump when the wall clock is set.
        let origin = (date: Date(), instant: ContinuousClock.now)
        self.init(sessions: sessions, hitchThreshold: hitchThreshold, hangThreshold: hangThreshold, limits: limits) {
            origin.date.addingTimeInterval((ContinuousClock.now - origin.instant).timeInterval)
        } watchedThread: {
            // Asked on the main actor, so the sampler is the main thread's.
            (CFRunLoopGetMain(), MachThreadStackSampler.currentThread())
        }
    }

    /// A recorder that dates what it records by `now` and watches the thread `watchedThread`
    /// gives.
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions.
    ///   - hitchThreshold: The shortest stall recorded.
    ///   - hangThreshold: The shortest stall recorded as a hang.
    ///   - limits: The bounds of one session's recording.
    ///   - now: The time an interval begins and ends at, checked against the session's expiry.
    ///   - watchedThread: The run loop to watch and the sampler of its thread, asked as each
    ///     recording starts.
    package init(
        sessions: DebugDrawerSessions,
        hitchThreshold: Duration,
        hangThreshold: Duration,
        limits: Limits,
        now: @escaping @Sendable () -> Date,
        watchedThread: @escaping @MainActor () -> (runLoop: CFRunLoop, sampler: any StackSampler)
    ) {
        precondition(hitchThreshold > .zero, "The hitch threshold must be positive")
        precondition(hitchThreshold <= hangThreshold, "The hitch threshold must be no longer than the hang threshold")
        self.hitchThreshold = hitchThreshold
        self.hangThreshold = hangThreshold
        self.now = now
        self.watchedThread = watchedThread
        inbox = SignpostInbox(limits: limits, now: now)
        snapshot = Self.empty(hitchThreshold: hitchThreshold, hangThreshold: hangThreshold, limits: limits)
        let wakeUps = inbox.wakeUps
        Task { [weak self] in
            for await _ in wakeUps {
                self?.collect()
            }
        }
        // The sessions are main-actor isolated and publish from there.
        sessionObservation = sessions.$snapshot.sink { [weak self] state in
            MainActor.assumeIsolated {
                self?.follow(state)
            }
        }
    }

    deinit {
        inbox.finish()
    }

    /// Does what `command` asks.
    ///
    /// - Parameter command: What to do.
    public func perform(_ command: Command) {
        switch command {
        case .start:
            guard let openSession, snapshot.sessionID != openSession.id else { return }
            start(in: openSession)
        case .stop:
            discard()
        case .export:
            guard snapshot.isRecording else { return }
            collect()
            let export = Export(date: now(), stalls: snapshot.stalls.count, intervals: snapshot.intervals.count)
            snapshot.exports.append(export)
            let (stalls, intervals) = (export.stalls, export.intervals)
            Self.logger.notice("Performance traces exported: \(stalls, privacy: .public) stalls, \(intervals, privacy: .public) intervals")
        }
    }

    /// Begins an interval named `name`, as `OSSignposter.beginInterval(_:)` does, which
    /// ``endInterval(_:)`` ends; recorded only when a sidecar's recording runs as it begins and
    /// as it ends, in the same session.
    ///
    /// Call it from any thread or actor; it returns at once.
    ///
    /// - Parameter name: What the interval times, a string literal: no value from the app's data
    ///   reaches the sidecar.
    /// - Returns: The interval, for ``endInterval(_:)``.
    /// - Complexity: O(1).
    public nonisolated func beginInterval(_ name: StaticString) -> IntervalState {
        IntervalState(name: name, recording: inbox.begin())
    }

    /// Ends `interval`, recording it with its duration if a sidecar's recording runs in the
    /// session it began in.
    ///
    /// Call it from any thread or actor; it returns at once.
    ///
    /// - Parameter interval: What ``beginInterval(_:)`` returned.
    /// - Complexity: O(1) amortized.
    public nonisolated func endInterval(_ interval: IntervalState) {
        guard let recording = interval.recording else { return }
        inbox.end(interval.name, recording)
    }

    /// Takes the file the receiver writes the snapshot to, and removes what is there: a recorder
    /// made fresh holds nothing, so anything there was left by a launch killed during a session.
    package func attach(snapshotFile file: URL) {
        snapshotFile = file
        removeSnapshotFile()
    }

    /// Starts the monitor and the inbox for `session`, empty.
    private func start(in session: DebugDrawerSession) {
        // A recording of another session still running is that session's to delete first.
        discard()
        let thread = watchedThread()
        let sessionID = session.id
        monitor = HangMonitor(runLoop: thread.runLoop, sampler: thread.sampler, threshold: hitchThreshold) { [weak self] hang in
            // Named after the observer returns, rather than inside it, where the run loop is about
            // to sleep or start work: naming the frames is work of its own.
            Task { @MainActor in
                self?.record(hang, in: sessionID)
            }
        }
        inbox.open(session)
        snapshot = Snapshot(
            sessionID: sessionID, executable: Self.executable, hitchThreshold: hitchThreshold, hangThreshold: hangThreshold,
            stalls: [], intervals: [],
            droppedStalls: 0, droppedIntervals: 0, limits: limits, exports: []
        )
        Self.logger.notice("Performance traces started for a sidecar's session")
    }

    /// Keeps `hang` with its frames named, if the session it was caught in still records and
    /// hadn't expired as it began.
    private func record(_ hang: DetectedHang, in sessionID: UUID) {
        guard snapshot.sessionID == sessionID, let openSession, openSession.id == sessionID, hang.date < openSession.expires else { return }
        collect()
        var recorded = snapshot
        let number = (recorded.stalls.last?.id ?? recorded.droppedStalls) + 1
        recorded.stalls.append(Stall(
            id: number,
            kind: hang.duration >= hangThreshold ? .hang : .hitch,
            began: hang.date,
            duration: hang.duration,
            frames: Symbolicator.frames(for: hang.addresses)
        ))
        while recorded.stalls.count > limits.stalls {
            recorded.stalls.removeFirst()
            recorded.droppedStalls += 1
        }
        snapshot = recorded
    }

    /// Follows the open session, and stops and deletes the recording when its session is over.
    private func follow(_ state: DebugDrawerSessionState) {
        openSession = state.session
        if let recording = snapshot.sessionID, state.session?.id != recording {
            discard()
        }
    }

    /// Stops recording and deletes everything recorded, in memory and on disk; does nothing while
    /// it isn't recording, so the empty snapshot the receiver serves then stays.
    private func discard() {
        guard snapshot.isRecording else { return }
        monitor?.stop()
        monitor = nil
        inbox.close()
        snapshot = Self.empty(hitchThreshold: hitchThreshold, hangThreshold: hangThreshold, limits: limits)
        // The receiver writes the empty snapshot after this, as it follows each change.
        removeSnapshotFile()
        Self.logger.notice("Performance traces stopped, and what they recorded deleted")
    }

    private func removeSnapshotFile() {
        guard let snapshotFile, FileManager.default.fileExists(atPath: snapshotFile.path) else { return }
        do {
            try FileManager.default.removeItem(at: snapshotFile)
        } catch {
            Self.logger.error("Couldn't remove the performance traces' file: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Takes the intervals the inbox recorded for the session into the snapshot.
    private func collect() {
        guard let sessionID = snapshot.sessionID else { return }
        let state = inbox.current()
        guard state.session?.id == sessionID, state.intervals != snapshot.intervals || state.dropped != snapshot.droppedIntervals else { return }
        // One assignment, so a reader never sees the intervals of one moment with the count of another.
        var collected = snapshot
        collected.intervals = state.intervals
        collected.droppedIntervals = state.dropped
        snapshot = collected
    }

    /// The file name of the app's executable.
    private nonisolated static let executable = Bundle.main.executableURL?.lastPathComponent

    private static func empty(hitchThreshold: Duration, hangThreshold: Duration, limits: Limits) -> Snapshot {
        Snapshot(
            sessionID: nil, executable: executable, hitchThreshold: hitchThreshold, hangThreshold: hangThreshold, stalls: [], intervals: [],
            droppedStalls: 0, droppedIntervals: 0, limits: limits, exports: []
        )
    }
}
