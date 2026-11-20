#if DEBUG
    import Combine
    import DebugDrawerNetwork
    import Foundation
    import os

    /// A scheduler whose time moves only when a test advances it: work scheduled on it runs inside
    /// `advance(by:)`, in the order it falls due, on the test's thread. A test that waits for the
    /// URL protocol to schedule something awaits `waitUntil(_:)`, which resumes once the scheduler's
    /// state meets its condition.
    final class ManualNetworkConditionScheduler: NetworkConditionScheduler {
        /// What the scheduler holds, as a test reads it.
        struct Snapshot: Sendable {
            /// How far the test has advanced time.
            var now: Duration = .zero
            /// Every delay asked for, in order, cancelled ones included.
            var delays: [Duration] = []
            /// How many scheduled items haven't run or been cancelled.
            var pendingCount = 0
            /// How many items were cancelled before they ran.
            var cancelledCount = 0
        }

        private struct Item: Sendable {
            let id: Int
            let due: Duration
            let work: @Sendable () -> Void
        }

        private struct Waiter: Sendable {
            let condition: @Sendable (Snapshot) -> Bool
            let continuation: CheckedContinuation<Void, Never>
        }

        private struct State: Sendable {
            var snapshot = Snapshot()
            var items: [Item] = []
            var nextID = 0
            var waiters: [Waiter] = []

            /// Takes out the waiters whose condition now holds.
            mutating func readyWaiters() -> [Waiter] {
                snapshot.pendingCount = items.count
                let ready = waiters.filter { $0.condition(snapshot) }
                let current = snapshot
                waiters.removeAll { $0.condition(current) }
                return ready
            }
        }

        private let state = OSAllocatedUnfairLock(initialState: State())

        var snapshot: Snapshot {
            state.withLock { $0.snapshot }
        }

        func schedule(after delay: Duration, _ work: @escaping @Sendable () -> Void) -> AnyCancellable {
            let (id, ready) = state.withLock { state in
                let id = state.nextID
                state.nextID += 1
                state.items.append(Item(id: id, due: state.snapshot.now + delay, work: work))
                state.snapshot.delays.append(delay)
                return (id, state.readyWaiters())
            }
            ready.forEach { $0.continuation.resume() }
            return AnyCancellable { [state] in
                let ready = state.withLock { state -> [Waiter] in
                    guard state.items.contains(where: { $0.id == id }) else { return [] }
                    state.items.removeAll { $0.id == id }
                    state.snapshot.cancelledCount += 1
                    return state.readyWaiters()
                }
                ready.forEach { $0.continuation.resume() }
            }
        }

        /// Moves time forward by `duration`, running each item that falls due by then, earliest
        /// first, including any an item schedules within the window.
        func advance(by duration: Duration) {
            let target = state.withLock { $0.snapshot.now + duration }
            while true {
                let next = state.withLock { state -> Item? in
                    guard let item = state.items.filter({ $0.due <= target }).min(by: { ($0.due, $0.id) < ($1.due, $1.id) }) else {
                        return nil
                    }
                    state.items.removeAll { $0.id == item.id }
                    state.snapshot.now = item.due
                    return item
                }
                guard let next else { break }
                next.work()
                let ready = state.withLock { $0.readyWaiters() }
                ready.forEach { $0.continuation.resume() }
            }
            let ready = state.withLock { state in
                state.snapshot.now = target
                return state.readyWaiters()
            }
            ready.forEach { $0.continuation.resume() }
        }

        /// Returns once `condition` holds of the scheduler's state.
        func waitUntil(_ condition: @escaping @Sendable (Snapshot) -> Bool) async {
            await withCheckedContinuation { continuation in
                let isMet = state.withLock { state in
                    state.snapshot.pendingCount = state.items.count
                    guard !condition(state.snapshot) else { return true }
                    state.waiters.append(Waiter(condition: condition, continuation: continuation))
                    return false
                }
                if isMet { continuation.resume() }
            }
        }
    }
#endif
