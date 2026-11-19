#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation
    import os

    /// What a delivery brings the main queue: the calls kept since the last delivery, and the
    /// totals of every call since then.
    struct DiskIOBatch: Sendable {
        /// The calls recorded since the last delivery that the recorder still keeps, oldest
        /// first, with the ID of the oldest call it keeps.
        var events: CaptureBuffer<IOEvent>.Snapshot
        /// Every call since the last delivery, the ones the buffer dropped too.
        var totals = DiskIOTotals()
    }

    /// Collects file calls from any thread and hands them to the main thread in batches.
    ///
    /// A call appends its event to a `CaptureBuffer`, which keeps the newest `limit`, and counts
    /// it into the totals under a lock, then returns. The first event after a delivery schedules
    /// one block on the main queue, which takes the calls the buffer gained and the totals by
    /// then and sends them through ``batches``. So a burst of calls costs one main-queue hop, not
    /// one per call, and no timer runs.
    ///
    /// The totals sit behind a lock rather than in an actor: a swizzled call is synchronous and
    /// must return at once, and an actor would make each record an asynchronous hop, a task per
    /// call, that could reorder events sent back to back. `OSAllocatedUnfairLock` rather than
    /// `Mutex`, which needs iOS 18; switch to `Mutex` once iOS 18 is the minimum.
    final class DiskIORecorder: Sendable {
        /// The recorder the swizzled methods write to, for the life of the app.
        static let shared = DiskIORecorder()

        private struct State: Sendable {
            var totals = DiskIOTotals()
            var isDeliveryScheduled = false
            /// The buffer's ID after the newest call delivered.
            var deliveredEnd = CaptureBuffer<IOEvent>.ElementID(rawValue: 0)
        }

        /// The newest calls, bounded by the limit and by their paths' bytes.
        private let buffer: CaptureBuffer<IOEvent>
        private let state = OSAllocatedUnfairLock(initialState: State())
        // Sent only on the main queue, by the delivery a record schedules, so no two sends overlap.
        private nonisolated(unsafe) let delivered = PassthroughSubject<DiskIOBatch, Never>()

        /// A recorder that keeps at most `limit` events, whose paths add up to at most
        /// `byteLimit` bytes.
        ///
        /// - Parameters:
        ///   - limit: How many of the newest events the recorder keeps; its totals count all.
        ///   - byteLimit: How many bytes of paths the kept events hold, at most.
        init(limit: Int = 500, byteLimit: Int = 1_048_576) {
            buffer = CaptureBuffer(maxCount: limit, maxByteCount: byteLimit) { $0.capturedByteCount }
        }

        /// Each batch, on the main queue, once per turn of it that follows a record.
        ///
        /// Every subscriber gets the same batches; a batch sent before a subscription isn't sent
        /// to it.
        var batches: AnyPublisher<DiskIOBatch, Never> {
            delivered.eraseToAnyPublisher()
        }

        /// How many events the recorder keeps.
        var limit: Int {
            get { buffer.maxCount }
            set { buffer.maxCount = newValue }
        }

        /// How many bytes of paths the kept events hold, at most.
        var byteLimit: Int {
            get { buffer.maxByteCount }
            set { buffer.maxByteCount = newValue }
        }

        /// The kept events from `id` on, with the ID of the oldest kept.
        func snapshot(from id: CaptureBuffer<IOEvent>.ElementID) -> CaptureBuffer<IOEvent>.Snapshot {
            buffer.snapshot(from: id)
        }

        /// Forgets the kept events.
        func clear() {
            buffer.removeAll()
        }

        // Its own lock rather than a field of `state`: the buffer is appended before the totals
        // are counted, and the check must come before both.

        /// Whether ``record(_:)`` keeps what it is given: from the start, and between an install
        /// and an uninstall. A swizzle other code made on top of the plugin's keeps the plugin's
        /// method in the chain after an uninstall, and its calls are dropped here.
        let isRecording = OSAllocatedUnfairLock(initialState: true)

        /// Keeps `event` and counts it into the next batch's totals.
        ///
        /// - Complexity: Amortized O(1).
        func record(_ event: IOEvent) {
            guard isRecording.withLock({ $0 }) else { return }
            buffer.append(event)
            let schedulesDelivery = state.withLock { state in
                state.totals.add(event)
                guard !state.isDeliveryScheduled else { return false }
                state.isDeliveryScheduled = true
                return true
            }
            if schedulesDelivery {
                // A bare block on the main queue rather than a Combine signal received on it: with
                // the main thread idle every call is a delivery of its own, and the subject and
                // `receive(on:)` added allocations to each. A run-loop source or observer would
                // still wake the main thread once per delivery, and never fires where the main
                // thread serves only the main queue (`dispatchMain()`).
                DispatchQueue.main.async { [self] in delivered.send(takePending()) }
            }
        }

        private func takePending() -> DiskIOBatch {
            // The flag clears before the snapshot, so a call recorded after the snapshot finds it
            // clear and schedules the next delivery.
            let (totals, start) = state.withLock { state in
                state.isDeliveryScheduled = false
                return (state.totals.taken(), state.deliveredEnd)
            }
            let events = buffer.snapshot(from: start)
            state.withLock { $0.deliveredEnd = max($0.deliveredEnd, events.endID) }
            return DiskIOBatch(events: events, totals: totals)
        }
    }

    extension DiskIOTotals {
        /// Returns these totals and starts them over.
        fileprivate mutating func taken() -> Self {
            defer { self = Self() }
            return self
        }
    }

    extension IOEvent {
        /// What the call costs the recorder's byte bound: its paths.
        fileprivate var capturedByteCount: Int {
            path.utf8.count + (destination?.utf8.count ?? 0)
        }
    }
#endif
