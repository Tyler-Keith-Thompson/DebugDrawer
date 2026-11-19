#if DEBUG
    import CoreFoundation

    /// The first frame is in the first time the main run loop is about to sleep: layout and the
    /// Core Animation commit for the first frame happen before that.
    @MainActor
    final class _FirstFrameObserver: FirstFrameObserver {
        /// The observer added to the main run loop while waiting, or `nil`.
        private(set) var runLoopObserver: CFRunLoopObserver?

        func start(_ handler: @escaping @MainActor @Sendable () -> Void) {
            guard runLoopObserver == nil else { return }
            let observer = CFRunLoopObserverCreateWithHandler(
                nil, CFRunLoopActivity.beforeWaiting.rawValue, false, CFIndex.max
            ) { _, _ in
                MainActor.assumeIsolated { handler() }
            }
            runLoopObserver = observer
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }

        func stop() {
            guard let observer = runLoopObserver else { return }
            CFRunLoopObserverInvalidate(observer)
            runLoopObserver = nil
        }
    }
#endif
