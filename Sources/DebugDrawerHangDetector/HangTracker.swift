/// When a run loop's thread is stuck: the time between two of its checkpoints, measured from
/// the checkpoints the run loop reports and the ticks of a watcher thread.
///
/// A value with no clock of its own: every call takes the instant it happened at, so tests
/// step it by hand. `HangMonitor` calls it from the run loop's observer and from its watcher,
/// behind one lock.
package struct HangTracker: Equatable, Sendable {
    /// A stretch that went past the threshold, ended at a checkpoint.
    package struct Hang: Equatable, Sendable {
        package let duration: Duration
        /// Whether the watcher captured the thread's stack during it.
        package let isCaptured: Bool

        package init(duration: Duration, isCaptured: Bool) {
            self.duration = duration
            self.isCaptured = isCaptured
        }
    }

    /// What the thread is doing, as far as its run loop has said.
    package enum Phase: Equatable, Sendable {
        /// The run loop hasn't waited yet. The first pass is the app's launch, which Launch
        /// Time measures, so nothing in it counts.
        case launching
        /// Asleep in the run loop, waiting for work.
        case waiting
        /// Working since `since`; `isCaptured` once the watcher has taken its stack.
        case busy(since: SuspendingClock.Instant, isCaptured: Bool)
    }

    /// How many times the watcher wakes per threshold: a hang's stack is captured at most a
    /// quarter of a threshold after it crosses it.
    package static let ticksPerThreshold = 4

    /// The shortest stretch that counts as a hang. Must be positive.
    package var threshold: Duration
    package private(set) var phase: Phase = .launching
    /// When the watcher last woke, which tells a hang from the process being stopped.
    private var lastTick: SuspendingClock.Instant?

    package init(threshold: Duration) {
        self.threshold = threshold
    }

    /// How long the watcher sleeps between ticks.
    package var tickInterval: Duration {
        threshold / Self.ticksPerThreshold
    }

    /// The run loop reached a checkpoint at `now`: the stretch before it ends, and another
    /// begins unless the run loop is about to wait.
    ///
    /// - Parameters:
    ///   - now: When the checkpoint happened.
    ///   - isAboutToWait: Whether the run loop goes to sleep next (`kCFRunLoopBeforeWaiting`).
    /// - Returns: The stretch that ended, if it was at least the threshold long and the
    ///   process wasn't stopped during it.
    package mutating func checkpoint(at now: SuspendingClock.Instant, isAboutToWait: Bool) -> Hang? {
        var ended: Hang?
        if case let .busy(since, isCaptured) = phase, now - since >= threshold, !wasStopped(at: now) {
            ended = Hang(duration: now - since, isCaptured: isCaptured)
        }
        switch (phase, isAboutToWait) {
        case (.launching, false):
            break
        case (_, true):
            phase = .waiting
        case (_, false):
            phase = .busy(since: now, isCaptured: false)
        }
        return ended
    }

    /// The watcher woke at `now`: whether it should capture the thread's stack, which it does
    /// once per hang, as soon as the stretch reaches the threshold.
    package mutating func tick(at now: SuspendingClock.Instant) -> Bool {
        defer { lastTick = now }
        guard case let .busy(since, isCaptured) = phase else { return false }
        if wasStopped(at: now) {
            // The time the process was stopped isn't the thread's: count from now.
            phase = .busy(since: now, isCaptured: false)
            return false
        }
        guard !isCaptured, now - since >= threshold else { return false }
        phase = .busy(since: since, isCaptured: true)
        return true
    }

    /// Whether the watcher missed so many ticks by `now` that the whole process must have been
    /// stopped (at a debugger's breakpoint, or suspended in the background): a watcher that
    /// runs wakes every `tickInterval`, hang or not.
    private func wasStopped(at now: SuspendingClock.Instant) -> Bool {
        guard let lastTick else { return false }
        return now - lastTick > threshold + tickInterval
    }
}
