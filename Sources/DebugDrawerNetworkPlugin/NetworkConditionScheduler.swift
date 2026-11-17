#if DEBUG
    import Combine
    import Foundation

    /// Runs work after a delay: the latency and the bandwidth cap a profile adds are scheduled
    /// through it, so tests replace it with a scheduler they advance by hand.
    protocol NetworkConditionScheduler: Sendable {
        /// Runs `work` once, `delay` from now, on a queue of the scheduler's choosing, unless the
        /// returned value is cancelled first.
        func schedule(after delay: Duration, _ work: @escaping @Sendable () -> Void) -> AnyCancellable
    }

    // A one-shot DispatchSourceTimer rather than a Combine `delay(for:scheduler:)` pipeline: the
    // same timer underneath, without a subscription to keep alive, and cancelling it is one call.
    // Sleeping a task or a dispatch queue's delayed submission are out: the charter forbids them,
    // and a delayed submission can't be cancelled.

    /// Schedules on a dispatch timer on a queue of its own, with no leeway, so a latency is
    /// waited out as set.
    struct _NetworkConditionScheduler: NetworkConditionScheduler {
        private let queue = DispatchQueue(label: "DebugDrawerNetworkPlugin.NetworkConditionScheduler", qos: .userInitiated)

        func schedule(after delay: Duration, _ work: @escaping @Sendable () -> Void) -> AnyCancellable {
            let timer = DispatchSource.makeTimerSource(queue: queue)
            let nanoseconds = max(Int(clamping: delay.nanoseconds), 0)
            timer.schedule(deadline: .now() + .nanoseconds(nanoseconds), leeway: .nanoseconds(0))
            timer.setEventHandler(handler: work)
            timer.resume()
            return AnyCancellable { timer.cancel() }
        }
    }

    extension Duration {
        /// The duration in whole nanoseconds, rounded toward zero; past what an `Int64` holds,
        /// its largest or smallest value.
        var nanoseconds: Int64 {
            let (seconds, attoseconds) = components
            guard seconds < Int64.max / 1_000_000_000 else { return .max }
            guard seconds > Int64.min / 1_000_000_000 else { return .min }
            return seconds * 1_000_000_000 + attoseconds / 1_000_000_000
        }
    }
#endif
