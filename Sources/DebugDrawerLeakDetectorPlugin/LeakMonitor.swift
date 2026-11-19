#if DEBUG
    import Dispatch
    import Foundation

    /// Feeds a `LeakTracker` the lifecycle events of real objects: a sentinel on each tracked or
    /// dismissed object for its deallocation, the run loop's turns for the check after a dismissal.
    ///
    /// Main-actor isolated, like the view controllers it watches and the drawer it reports to; an
    /// object tracked on another thread is recorded through the main queue.
    @MainActor
    final class LeakMonitor {
        private var tracker = LeakTracker()
        /// The view controllers `tracker` knows as dismissed, held weakly, by sentinel identifier.
        private var viewControllers: [UInt64: DismissedViewController] = [:]
        private let turns: any RunLoopTurnSource
        private let now: @MainActor () -> Date
        private let onChange: @MainActor (LeakChange) -> Void

        /// - Parameters:
        ///   - turns: The ends of the run loop's turns; observed from now on.
        ///   - now: The date a suspect is flagged at.
        ///   - onChange: Called each time the suspects change, with what was flagged.
        init(
            turns: any RunLoopTurnSource,
            now: @escaping @MainActor () -> Date = Date.init,
            onChange: @escaping @MainActor (LeakChange) -> Void
        ) {
            self.turns = turns
            self.now = now
            self.onChange = onChange
            turns.observe { [weak self] in self?.endTurn() }
        }

        /// Every suspect, the most recently flagged first.
        var suspects: [LeakSuspect] {
            tracker.suspects
        }

        /// Stops observing the run loop's turns and forgets every object it counted and every
        /// view controller it was waiting to check. Calling it again does nothing.
        func stop() {
            turns.stop()
            tracker = LeakTracker()
            viewControllers = [:]
        }

        /// Counts `object` among the live instances of its class, of which at most `maxCount`
        /// should be alive, until it deallocates. From any thread; off the main thread, it is
        /// counted once the main queue gets to it.
        nonisolated func track(_ object: AnyObject, maxCount: Int) {
            Self.track(object, maxCount: maxCount) { [weak self] in self }
        }

        /// Counts `object` in the monitor `monitor` returns on the main actor, which needn't exist
        /// until then: how an object tracked off the main thread reaches a monitor only the main
        /// actor can make.
        nonisolated static func track(_ object: AnyObject, maxCount: Int, in monitor: @escaping @MainActor @Sendable () -> LeakMonitor?) {
            let type = TrackedClass(of: object)
            let id = LifetimeSentinel.attached(to: object) { monitor()?.end($0) }.id
            if Thread.isMainThread {
                MainActor.assumeIsolated { monitor()?.record(id, of: type, maxCount: maxCount) }
            } else {
                DispatchQueue.main.async { monitor()?.record(id, of: type, maxCount: maxCount) }
            }
        }

        /// Notes that `viewController` left the screen for good, to be flagged if it is still
        /// alive, and `isDetached` still holds, at the end of the next turn.
        ///
        /// - Parameters:
        ///   - viewController: The view controller dismissed, or removed from its parent.
        ///   - isDetached: Whether the view controller is still off screen, rather than shown again.
        func dismiss(_ viewController: AnyObject, isDetached: @escaping @MainActor (AnyObject) -> Bool) {
            let id = LifetimeSentinel.attached(to: viewController) { [weak self] in self?.end($0) }.id
            viewControllers[id] = DismissedViewController(object: viewController, isDetached: isDetached)
            tracker.dismiss(id, of: TrackedClass(of: viewController))
        }

        private func record(_ id: UInt64, of type: TrackedClass, maxCount: Int) {
            let flagged = tracker.track(id, of: type, maxCount: maxCount, at: now())
            if !flagged.isEmpty {
                onChange(LeakChange(suspects: tracker.suspects, flagged: flagged))
            }
        }

        private func end(_ id: UInt64) {
            let before = tracker.suspects
            tracker.end(id)
            viewControllers[id] = nil
            let after = tracker.suspects
            if after != before {
                onChange(LeakChange(suspects: after, flagged: []))
            }
        }

        private func endTurn() {
            let due = tracker.dueForCheck
            // Most turns have nothing dismissed: they cost this check.
            guard !due.isEmpty || tracker.isWaitingForTurn else { return }
            let before = tracker.suspects
            let detached = Set(due.filter { viewControllers[$0]?.isStillDetached == true })
            let flagged = tracker.endTurn(at: now(), detached: detached)
            let remaining = tracker.dismissedIDs
            viewControllers = viewControllers.filter { remaining.contains($0.key) }
            if tracker.isWaitingForTurn {
                turns.wakeUp()
            }
            let after = tracker.suspects
            if after != before {
                onChange(LeakChange(suspects: after, flagged: flagged))
            }
        }
    }

    /// The suspects after a change, and the ones it flagged, which get a toast.
    struct LeakChange: Equatable, Sendable {
        /// Every suspect, the most recently flagged first.
        let suspects: [LeakSuspect]
        /// The suspects flagged by this change, or whose count grew over the limit.
        let flagged: [LeakSuspect]
    }

    extension LeakMonitor {
        /// A dismissed view controller, held weakly, and how to tell whether it is still off screen.
        fileprivate struct DismissedViewController {
            weak var object: AnyObject?
            let isDetached: @MainActor (AnyObject) -> Bool

            /// Whether it is still alive and off screen.
            @MainActor var isStillDetached: Bool {
                object.map(isDetached) ?? false
            }
        }
    }
#endif
