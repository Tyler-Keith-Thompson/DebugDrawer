#if DEBUG && (os(macOS) || os(iOS))
    import CoreFoundation

    /// Calls `action` once per pass of the main run loop, in every common mode (a live resize, a
    /// scroll or a drag included), after the pass's layout and Core Animation commit, while it is
    /// started.
    ///
    /// The overlays read the app's view frames here rather than on a display link: an app that
    /// sits idle wakes nothing, and everything that moves a view does so in a pass. A change the
    /// action makes to what it draws is shown by the next pass, which `wakeUp()` asks for.
    @MainActor
    final class RunLoopPassObserver {
        /// After Core Animation's commit observer (order 2,000,000), so layout is done.
        private static let order: CFIndex = 2_100_000

        private let action: @MainActor () -> Void
        private var observer: CFRunLoopObserver?

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        var isStarted: Bool {
            observer != nil
        }

        func start() {
            guard observer == nil else { return }
            // Before waiting and on exit, as Core Animation commits: a pass that handled a source
            // polls again without waiting, and exits a nested run loop's mode without sleeping.
            let activities = CFRunLoopActivity.beforeWaiting.rawValue | CFRunLoopActivity.exit.rawValue
            let observer = CFRunLoopObserverCreateWithHandler(nil, activities, true, Self.order) { [weak self] _, _ in
                // The observer is added to the main run loop, so it runs on the main thread.
                MainActor.assumeIsolated { self?.action() }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            self.observer = observer
        }

        func stop() {
            guard let observer else { return }
            CFRunLoopObserverInvalidate(observer)
            self.observer = nil
        }

        /// Asks for another pass, so a change made in this one is drawn.
        func wakeUp() {
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }

        isolated deinit {
            stop()
        }
    }
#endif
