import CoreFoundation
import Foundation

/// Watches a run loop's thread for hangs: an observer on the run loop marks each checkpoint,
/// and a watcher thread wakes a few times per threshold, captures the stuck thread's stack
/// once per hang, and lets the observer report it when the thread gets going again.
///
/// The observer runs on the watched thread, so all it does is read the clock and take an
/// uncontended lock. The monitor stops (its observers removed, its watcher thread ended) on
/// ``stop()``, or when it is released.
package final class HangMonitor {
    /// The watcher thread's name.
    package static let watcherName = "DebugDrawer hang watcher"

    private let state: HangMonitorState
    /// The observers on the watched run loop: one that starts each stretch, one that ends it.
    package let observers: [CFRunLoopObserver]
    /// The watcher thread, until ``stop()`` has joined it.
    private var watcher: pthread_t?

    /// Starts watching `runLoop`, whose thread `sampler` samples.
    ///
    /// - Parameters:
    ///   - runLoop: The run loop of the thread to watch: the main one, in the app.
    ///   - sampler: Captures that thread's stack.
    ///   - threshold: The shortest stretch that counts as a hang. Traps unless positive.
    ///   - onHang: Called on the watched thread, after a checkpoint, for each hang.
    package init(
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
        watcher = Self.startWatcher {
            started.signal()
            state.watch(sampler)
        }
        // Returns once the watcher runs, so a hang right after install is watched.
        if watcher != nil {
            started.wait()
        }
    }

    deinit {
        stop()
    }

    /// Stops watching: removes the observers from the run loop, wakes the watcher thread and
    /// waits for it to end. Calling it again does nothing.
    package func stop() {
        for observer in observers {
            CFRunLoopObserverInvalidate(observer)
        }
        state.stop()
        guard let watcher else { return }
        self.watcher = nil
        // Not long: the stop wakes the watcher, which then finds itself stopped and returns.
        pthread_join(watcher, nil)
    }

    /// Starts the watcher thread running `body`.
    ///
    /// A POSIX thread rather than a `Thread`, so ``stop()`` can join it: once it returns, the
    /// thread is gone, not merely about to end.
    private static func startWatcher(_ body: @escaping @Sendable () -> Void) -> pthread_t? {
        var attributes = pthread_attr_t()
        pthread_attr_init(&attributes)
        defer { pthread_attr_destroy(&attributes) }
        // It must run while the watched thread is stuck, so it outranks the app's other work.
        pthread_attr_set_qos_class_np(&attributes, QOS_CLASS_USER_INTERACTIVE, 0)
        let context = Unmanaged.passRetained(WatcherBody(run: body)).toOpaque()
        var thread: pthread_t?
        let result = pthread_create(&thread, &attributes, { context in
            let body = Unmanaged<WatcherBody>.fromOpaque(context).takeRetainedValue()
            pthread_setname_np(HangMonitor.watcherName)
            body.run()
            return nil
        }, context)
        guard result == 0 else {
            Unmanaged<WatcherBody>.fromOpaque(context).release()
            return nil
        }
        return thread
    }

    /// The shortest stretch that counts as a hang, from the next checkpoint on. Traps unless
    /// positive.
    package var threshold: Duration {
        get { state.threshold }
        set { state.threshold = newValue }
    }
}

/// What the watcher thread runs, handed to it through `pthread_create`'s context pointer.
private final class WatcherBody {
    let run: @Sendable () -> Void

    init(run: @escaping @Sendable () -> Void) {
        self.run = run
    }
}
