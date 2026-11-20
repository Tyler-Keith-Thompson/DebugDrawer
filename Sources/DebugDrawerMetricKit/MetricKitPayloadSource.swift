import Foundation

// Real in every build: the receiver's MetricKit capability subscribes through it in release, and
// the MetricKit plugin in debug. Package-visible, as the plugin and the capability (and their
// tests, which hand them fakes) use it and a host doesn't.

/// A payload as it arrives: its kind, its `jsonRepresentation()`, and the period it covers when
/// the sender knows it (MetricKit's objects do; JSON added by hand names it inside).
package struct ReceivedMetricKitPayload: Equatable, Sendable {
    package let kind: MetricKitPayloadKind
    package let json: Data
    package var begin: Date?
    package var end: Date?

    package init(kind: MetricKitPayloadKind, json: Data, begin: Date? = nil, end: Date? = nil) {
        self.kind = kind
        self.json = json
        self.begin = begin
        self.end = end
    }
}

/// Delivers MetricKit's payloads: the ones the system still holds when subscribing, then each as
/// it arrives, at most once a day for metrics and as they happen for diagnostics.
@MainActor
package protocol MetricKitPayloadSource: AnyObject {
    /// Starts delivering payloads to `receive`, on the main actor: first the ones the system still
    /// holds, then each new one.
    func subscribe(_ receive: @escaping @MainActor ([ReceivedMetricKitPayload]) -> Void)
    /// Stops delivering payloads until the next ``subscribe(_:)``.
    func unsubscribe()
}
