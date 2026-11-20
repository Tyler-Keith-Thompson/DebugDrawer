import DebugDrawerReceiver
import Foundation
import os

// The part of the recording the host's signposts reach, from any thread. It holds the session's
// intervals behind a lock, bounded as each one is added, and wakes the model on the main actor
// through a stream that keeps one wake-up, so a burst of intervals is one snapshot. While nothing
// records, a begin is one uncontended lock and returns an interval that records nothing, so an
// interval begun before the recording started, or in another session, is never kept. A lock rather
// than an actor: a signpost returns at once, and a hop per call would cost more than the interval
// it marks. `OSAllocatedUnfairLock` rather than `Mutex`, which needs iOS 18; switch once iOS 18 is
// the minimum.

/// The session an interval began in, and when.
struct SignpostRecording: Sendable {
    let session: UUID
    let began: Date
}

final class SignpostInbox: Sendable {
    struct State {
        var session: DebugDrawerSession?
        var intervals: [PerformanceTraces.SignpostInterval] = []
        var dropped = 0
        var nextID = 1
    }

    let limits: PerformanceTraces.Limits
    let wakeUps: AsyncStream<Void>

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let now: @Sendable () -> Date
    private let wake: AsyncStream<Void>.Continuation

    init(limits: PerformanceTraces.Limits, now: @escaping @Sendable () -> Date) {
        self.limits = limits
        self.now = now
        (wakeUps, wake) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// Whether intervals are recorded.
    var isRecording: Bool {
        state.withLock { $0.session != nil }
    }

    /// Records the intervals that end in `session` from now on, starting empty.
    func open(_ session: DebugDrawerSession) {
        state.withLock { $0 = State(session: session) }
    }

    /// Stops recording and forgets every interval.
    func close() {
        state.withLock { $0 = State() }
    }

    /// Stops recording and the wake-ups.
    func finish() {
        close()
        wake.finish()
    }

    /// The intervals now.
    func current() -> State {
        state.withLock { $0 }
    }

    /// The session an interval begun now belongs to and when it began, or `nil` while nothing
    /// records.
    func begin() -> SignpostRecording? {
        guard let session = state.withLock({ $0.session?.id }) else { return nil }
        return SignpostRecording(session: session, began: now())
    }

    /// Keeps the interval `name` that began as `recording` says and ends now, if its session still
    /// records and hasn't expired.
    func end(_ name: StaticString, _ recording: SignpostRecording) {
        let finished = now()
        let name = name.description
        let limits = limits
        let kept = state.withLock { state -> Bool in
            guard let session = state.session, session.id == recording.session, finished < session.expires else { return false }
            let duration = Duration.seconds(max(finished.timeIntervalSince(recording.began), 0))
            state.intervals.append(PerformanceTraces.SignpostInterval(id: state.nextID, name: name, began: recording.began, duration: duration))
            state.nextID += 1
            while state.intervals.count > limits.intervals {
                state.intervals.removeFirst()
                state.dropped += 1
            }
            return true
        }
        if kept {
            wake.yield()
        }
    }
}
