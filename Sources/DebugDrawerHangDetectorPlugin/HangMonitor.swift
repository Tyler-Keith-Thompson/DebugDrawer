#if DEBUG
    import CoreFoundation
    import Foundation

    /// Watches a run loop's thread for hangs: an observer on the run loop marks each checkpoint,
    /// and a watcher thread wakes a few times per threshold, captures the stuck thread's stack
    /// once per hang, and lets the observer report it when the thread gets going again.
    ///
    /// The observer runs on the watched thread, so all it does is read the clock and take an
    /// uncontended lock. The monitor stops (its observers removed, its watcher thread ended) when
    /// it is released.
    final class HangMonitor {
        private let state: HangMonitorState
        private let observers: [CFRunLoopObserver]

        /// Starts watching `runLoop`, whose thread `sampler` samples.
        ///
        /// - Parameters:
        ///   - runLoop: The run loop of the thread to watch: the main one, in the app.
        ///   - sampler: Captures that thread's stack.
        ///   - threshold: The shortest stretch that counts as a hang. Traps unless positive.
        ///   - onHang: Called on the watched thread, after a checkpoint, for each hang.
        init(
            runLoop: CFRunLoop,
            sampler: some StackSampler,
            threshold: Duration,
            onHang: @escaping @Sendable (DetectedHang) -> Void
        ) {
            let state = HangMonitorState(threshold: threshold)
            self.state = state
            // Two observers, so each checkpoint is measured where it is: the one that starts a
            // stretch runs before every other observer, and the one that ends it before the run
            // loop sleeps runs after every other (Core Animation commits the frame there, which is
            // the thread's work too).
            let starts = CFRunLoopActivity([.entry, .beforeTimers, .beforeSources, .afterWaiting])
            let ends = CFRunLoopActivity([.beforeWaiting, .exit])
            observers = [(starts, CFIndex.min), (ends, CFIndex.max)].map { activities, order in
                CFRunLoopObserverCreateWithHandler(nil, activities.rawValue, true, order) { _, activity in
                    if let hang = state.checkpoint(isAboutToWait: activity == .beforeWaiting) {
                        onHang(hang)
                    }
                }
            }
            for observer in observers {
                CFRunLoopAddObserver(runLoop, observer, .commonModes)
            }
            let started = DispatchSemaphore(value: 0)
            let watcher = Thread {
                Thread.current.name = "DebugDrawer hang watcher"
                started.signal()
                state.watch(sampler)
            }
            // It must run while the watched thread is stuck, so it outranks the app's other work.
            watcher.qualityOfService = .userInteractive
            watcher.start()
            // Returns once the watcher runs, so a hang right after install is watched.
            started.wait()
        }

        deinit {
            for observer in observers {
                CFRunLoopObserverInvalidate(observer)
            }
            state.stop()
        }

        /// The shortest stretch that counts as a hang, from the next checkpoint on. Traps unless
        /// positive.
        var threshold: Duration {
            get { state.threshold }
            set { state.threshold = newValue }
        }
    }
#endif
