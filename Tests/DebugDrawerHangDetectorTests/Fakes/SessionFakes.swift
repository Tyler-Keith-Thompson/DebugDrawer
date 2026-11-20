#if DEBUG
    @testable import DebugDrawerReceiver
    import Foundation
    import os

    /// A wall clock the test moves by hand, which the sessions and the recording both read.
    final class MovableClock: SessionClock, Sendable {
        private let time: OSAllocatedUnfairLock<Date>

        init(_ start: Date) {
            time = OSAllocatedUnfairLock(initialState: start)
        }

        var now: Date {
            time.withLock { $0 }
        }

        func set(_ date: Date) {
            time.withLock { $0 = date }
        }
    }

    /// A session timer that fires when the test says.
    @MainActor
    final class ManualTimer: SessionTimer {
        private(set) var scheduled: Date?
        private var fire: (@MainActor () -> Void)?

        func schedule(at date: Date, _ fire: @escaping @MainActor () -> Void) {
            scheduled = date
            self.fire = fire
        }

        func cancel() {
            scheduled = nil
            fire = nil
        }

        /// Fires the scheduled call, as the system's timer would at the expiry date.
        func fireNow() {
            let fire = fire
            cancel()
            fire?()
        }
    }
#endif
