#if DEBUG
    import Foundation

    /// A payload as it arrives: its kind, its `jsonRepresentation()`, and the period it covers
    /// when the sender knows it (MetricKit's objects do; JSON added by hand names it inside).
    struct ReceivedMetricKitPayload: Equatable, Sendable {
        let kind: MetricKitPayloadKind
        let json: Data
        var begin: Date?
        var end: Date?
    }

    /// Delivers MetricKit's payloads: the ones the system still holds when subscribing, then each
    /// as it arrives, at most once a day for metrics and as they happen for diagnostics.
    @MainActor
    protocol MetricKitPayloadSource: AnyObject {
        /// Starts delivering payloads to `receive`, on the main actor: first the ones the system
        /// still holds, then each new one.
        func subscribe(_ receive: @escaping @MainActor ([ReceivedMetricKitPayload]) -> Void)
    }
#endif
