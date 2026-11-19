#if DEBUG
    import Foundation

    /// Drives the model while something shows its numbers: a call per displayed frame and a call
    /// each second. It is the model's clock as well as its frame source: the tick is when a second
    /// of frames is summed up and memory and threads are read. Tests pass a fake that records when
    /// it starts and stops and delivers the frames and ticks they hand it.
    @MainActor
    protocol PerformanceSampler: AnyObject {
        /// Starts calling `frame` with each frame's timestamp and the frame period, both in
        /// seconds, and `tick` once a second, until ``stop()``.
        func start(
            frame: @escaping @MainActor (_ timestamp: TimeInterval, _ frameDuration: TimeInterval) -> Void,
            tick: @escaping @MainActor () -> Void
        )

        /// Stops both; does nothing when stopped.
        func stop()
    }
#endif
