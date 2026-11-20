import Foundation
import os

/// A hang as the observer reports it: how long, when, and the stack the watcher captured.
package struct DetectedHang: Equatable, Sendable {
    package let duration: Duration
    /// When the hang began, by the wall clock.
    package let date: Date
    /// The thread's instruction and return addresses, innermost first; empty when the
    /// thread got going before the watcher looked.
    package let addresses: [UInt]
}

/// What a `HangMonitor`'s observers and its watcher thread share, behind one lock: the
/// tracker and the buffer a captured stack is written to.
///
/// `OSAllocatedUnfairLock` rather than `Mutex` (iOS 18) or an actor: the observer runs
/// synchronously on the watched thread, and the watcher must hold the lock while that thread
/// is stopped, which no `await` can do. An unfair lock donates the waiting thread's priority to
/// the holder, so the main thread waiting on the watcher doesn't wait behind lesser work.
/// Switch to `Mutex` once iOS 18 is the minimum.
package final class HangMonitorState: Sendable {
    /// The most frames a captured stack holds.
    package static let maximumFrames = 128

    private struct State {
        var tracker: HangTracker
        /// Where the watcher writes a captured stack; allocated once, so sampling allocates
        /// nothing while the thread is stopped.
        let frames: UnsafeMutableBufferPointer<UInt>
        var frameCount = 0
        var isStopped = false
    }

    private let state: OSAllocatedUnfairLock<State>
    /// Wakes the watcher early: when the threshold changes, and to stop.
    private let wake = DispatchSemaphore(value: 0)

    /// Traps unless `threshold` is positive.
    package init(threshold: Duration) {
        precondition(threshold > .zero, "The hang threshold must be positive")
        // The buffer is only touched under the lock, which makes the unchecked state safe.
        state = OSAllocatedUnfairLock(uncheckedState: State(
            tracker: HangTracker(threshold: threshold),
            frames: .allocate(capacity: Self.maximumFrames)
        ))
    }

    deinit {
        state.withLockUnchecked { $0.frames.deallocate() }
    }

    /// The tracker's threshold; setting it wakes the watcher, which then sleeps for the new
    /// interval. Traps unless positive.
    package var threshold: Duration {
        get { state.withLockUnchecked { $0.tracker.threshold } }
        set {
            precondition(newValue > .zero, "The hang threshold must be positive")
            state.withLockUnchecked { $0.tracker.threshold = newValue }
            wake.signal()
        }
    }

    /// A checkpoint of the watched run loop now: the hang it ended, if any, with the stack the
    /// watcher captured during it.
    package func checkpoint(isAboutToWait: Bool) -> DetectedHang? {
        let ended: (HangTracker.Hang, [UInt])? = state.withLockUnchecked { state in
            guard let hang = state.tracker.checkpoint(at: .now, isAboutToWait: isAboutToWait) else { return nil }
            return (hang, hang.isCaptured ? Array(state.frames.prefix(state.frameCount)) : [])
        }
        return ended.map { hang, addresses in
            DetectedHang(duration: hang.duration, date: Date.now.addingTimeInterval(-hang.duration.timeInterval), addresses: addresses)
        }
    }

    /// One wake of the watcher now: samples the thread if a hang has just crossed the
    /// threshold.
    package func tick(_ sampler: some StackSampler) {
        state.withLockUnchecked { state in
            guard state.tracker.tick(at: .now) else { return }
            // Held through the sample: the thread can't reach a checkpoint while stopped, and
            // the next checkpoint must find the whole stack written.
            state.frameCount = sampler.sample(into: state.frames)
        }
    }

    /// The watcher thread's body: a tick every `HangTracker.tickInterval` until stopped.
    package func watch(_ sampler: some StackSampler) {
        while let interval = state.withLockUnchecked({ $0.isStopped ? nil : $0.tracker.tickInterval }) {
            // The sampling period, not a wait for an event: the watcher has to look at the
            // thread while it is stuck, and nothing signals that.
            _ = wake.wait(timeout: .now() + interval.timeInterval)
            tick(sampler)
        }
    }

    /// Ends the watcher's loop at its next wake, which this brings forward.
    package func stop() {
        state.withLockUnchecked { $0.isStopped = true }
        wake.signal()
    }
}

extension Duration {
    /// The duration in seconds.
    package var timeInterval: TimeInterval {
        let (seconds, attoseconds) = components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
