#if DEBUG
    import Combine
    import Foundation

    /// Calls back once a second while the Energy monitor samples. Tests pass a fake that records
    /// when it starts and stops.
    @MainActor
    protocol SamplingTimer: AnyObject {
        /// Starts calling `tick` once a second, until ``stop()``.
        func start(_ tick: @escaping @MainActor () -> Void)

        /// Stops the ticks; does nothing when stopped.
        func stop()
    }

    /// The production timer: a 1 s timer on the main run loop, so every tick runs on the main
    /// actor. Performance has its own sampler: plugins share no helper target.
    @MainActor
    final class RunLoopSamplingTimer: SamplingTimer {
        private var cancellable: AnyCancellable?

        func start(_ tick: @escaping @MainActor () -> Void) {
            cancellable = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in tick() }
        }

        func stop() {
            cancellable?.cancel()
            cancellable = nil
        }
    }
#endif
