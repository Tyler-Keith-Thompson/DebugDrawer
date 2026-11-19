#if DEBUG
    import Combine
    @testable import DebugDrawerDiskIOPlugin
    import Foundation

    /// Recorded calls in memory, delivered when the test says so, with nothing swizzled. It
    /// records each switch the model flips, in order.
    @MainActor
    final class FakeDiskIOEventSource: DiskIOEventSource {
        /// What the model asked of the source, in the order asked.
        enum Request: Equatable {
            case start
            case stop
            case pause
            case resume
            case clear
        }

        @Published private(set) var events: [IOEvent] = []
        @Published private(set) var totals = DiskIOTotals()
        @Published var filterOp: IOEvent.Operation?
        @Published var mainThreadOnly = false
        @Published private(set) var isPaused = false
        /// Every request, first to last.
        private(set) var requests: [Request] = []

        /// Delivers `newCalls`, oldest first, as the recorder's batch would: they join the list at
        /// its newest end, and the totals count them.
        func deliver(_ newCalls: [IOEvent]) {
            objectWillChange.send()
            var updated = totals
            for call in newCalls {
                updated.add(call)
            }
            totals = updated
            events = newCalls.reversed() + events
        }

        func startRecording() {
            requests.append(.start)
        }

        func stopRecording() {
            requests.append(.stop)
            events = []
            totals = DiskIOTotals()
        }

        func setPaused(_ paused: Bool) {
            requests.append(paused ? .pause : .resume)
            isPaused = paused
        }

        func clear() {
            requests.append(.clear)
            events = []
            totals = DiskIOTotals()
        }
    }
#endif
