#if DEBUG
    import CoreFoundation

    /// The ends of the main run loop's turns, which is when the leak detector checks the view
    /// controllers dismissed in an earlier turn.
    @MainActor
    protocol RunLoopTurnSource: AnyObject {
        /// Calls `onTurnEnd` at the end of each turn from now on, until ``stop()``.
        func observe(_ onTurnEnd: @escaping @MainActor () -> Void)
        /// Stops calling what ``observe(_:)`` was given; calling it again does nothing.
        func stop()
        /// Makes the run loop turn again rather than sleep until its next event, so a view
        /// controller dismissed in this turn is checked at the end of the next one.
        func wakeUp()
    }

    /// The main run loop's turns: an observer of it about to wait, in every common mode.
    @MainActor
    final class MainRunLoopTurnSource: RunLoopTurnSource {
        /// The observer on the main run loop, while observing.
        private(set) var observer: CFRunLoopObserver?

        func observe(_ onTurnEnd: @escaping @MainActor () -> Void) {
            precondition(observer == nil, "A turn source has one observer at a time")
            // About to wait is the end of a turn: the run loop has handled what woke it, and the
            // autorelease pool's own observer drains as it waits. The order among observers doesn't
            // matter, since a view controller is checked a whole turn after it was dismissed.
            let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, _ in
                // The observer is on the main run loop, so it runs on the main thread.
                MainActor.assumeIsolated { onTurnEnd() }
            }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
            self.observer = observer
        }

        func stop() {
            guard let observer else { return }
            // Invalidating removes it from every run loop and mode it was added to.
            CFRunLoopObserverInvalidate(observer)
            self.observer = nil
        }

        func wakeUp() {
            // Called as the run loop is about to wait, this sends the message that ends the wait
            // at once, so the next turn starts without waiting for an event.
            CFRunLoopWakeUp(CFRunLoopGetMain())
        }
    }
#endif
