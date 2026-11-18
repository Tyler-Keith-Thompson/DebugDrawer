#if DEBUG
    import Combine
    import Foundation
    import os

    /// The calls recorded since the last delivery: the newest of them, and the totals of all.
    struct DiskIOBatch: Sendable {
        /// The newest calls, oldest first; a burst past the recorder's limit keeps only its end.
        var events: [IOEvent] = []
        /// Every call in the batch, the ones `events` dropped too.
        var totals = DiskIOTotals()
    }

    /// Collects file calls from any thread and hands them to the main thread in batches.
    ///
    /// A call appends its event to a buffer under a lock and returns. The first event after a
    /// delivery sends one signal through a Combine subject; ``batches`` receives it on the main
    /// queue and takes everything buffered by then. So a burst of calls costs one main-queue hop,
    /// not one per call, and no timer runs.
    ///
    /// The buffer sits behind a lock rather than in an actor: a swizzled call is synchronous and
    /// must return at once, and an actor would make each record an asynchronous hop, a task per
    /// call, that could reorder events sent back to back. `OSAllocatedUnfairLock` rather than
    /// `Mutex`, which needs iOS 18; switch to `Mutex` once iOS 18 is the minimum.
    final class DiskIORecorder: Sendable {
        /// The recorder the swizzled methods write to, for the life of the app.
        static let shared = DiskIORecorder()

        private struct State: Sendable {
            var pending = DiskIOBatch()
            var isDeliveryScheduled = false
            var limit: Int
        }

        private let state: OSAllocatedUnfairLock<State>
        // Sent only by the record that sets `isDeliveryScheduled`, and no other record sends
        // until the delivery that clears it, so no two sends overlap.
        private nonisolated(unsafe) let signal = PassthroughSubject<Void, Never>()

        /// A recorder that keeps at most about `limit` events between deliveries.
        ///
        /// - Parameter limit: How many of the newest events a batch keeps; its totals count all.
        init(limit: Int = 500) {
            state = OSAllocatedUnfairLock(initialState: State(limit: limit))
        }

        /// Each batch, on the main queue, once per turn of it that follows a record.
        ///
        /// Subscribe once: each subscription takes what is buffered when the signal reaches it,
        /// so a second would see the batches the first left, empty.
        var batches: AnyPublisher<DiskIOBatch, Never> {
            signal
                .receive(on: DispatchQueue.main)
                .map { [self] in takePending() }
                .eraseToAnyPublisher()
        }

        /// Changes how many events a batch keeps.
        func setLimit(_ limit: Int) {
            state.withLock { $0.limit = limit }
        }

        /// Buffers `event` for the next batch.
        ///
        /// - Complexity: Amortized O(1).
        func record(_ event: IOEvent) {
            let schedulesDelivery = state.withLock { state in
                state.pending.events.append(event)
                state.pending.totals.add(event)
                // Trimmed in halves, so a main thread that stays busy costs a shift per `limit`
                // events rather than one per event.
                if state.pending.events.count > 2 * max(state.limit, 1) {
                    state.pending.events.removeFirst(state.pending.events.count - state.limit)
                }
                guard !state.isDeliveryScheduled else { return false }
                state.isDeliveryScheduled = true
                return true
            }
            if schedulesDelivery { signal.send() }
        }

        private func takePending() -> DiskIOBatch {
            state.withLock { state in
                state.isDeliveryScheduled = false
                var batch = DiskIOBatch()
                swap(&batch, &state.pending)
                if batch.events.count > state.limit {
                    batch.events.removeFirst(batch.events.count - state.limit)
                }
                return batch
            }
        }
    }
#endif
