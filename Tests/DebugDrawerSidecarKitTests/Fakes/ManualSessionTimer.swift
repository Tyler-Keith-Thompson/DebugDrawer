#if DEBUG
    import DebugDrawerReceiver
    import Foundation

    /// A session timer that fires when the test says: it keeps the date and the call scheduled
    /// last.
    @MainActor
    final class ManualSessionTimer: SessionTimer {
        private(set) var scheduled: Date?
        private var fireCall: (@MainActor () -> Void)?

        func schedule(at date: Date, _ fire: @escaping @MainActor () -> Void) {
            scheduled = date
            fireCall = fire
        }

        func cancel() {
            scheduled = nil
            fireCall = nil
        }

        /// Fires the call scheduled, once.
        func fire() {
            let call = fireCall
            cancel()
            call?()
        }
    }
#endif
