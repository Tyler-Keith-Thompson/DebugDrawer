import DebugDrawerReceiver
import Foundation

// The capability lives with the MetricKit payloads' vocabulary, not in the receiver: the receiver
// knows models, not plugins, and a host that forwards no payloads links none of this. Its commands
// only delete the app's copies of what the system reported, which no session end should bring
// back, so its scope is persistent.

public extension DebugDrawerReceiverCapability {
    /// The MetricKit payloads the app receives from now on, crash diagnostics among them, and
    /// those MetricKit still holds from before: each redacted by `redaction` and kept in
    /// `directory` across launches, the newest `capacity`, and served to a sidecar in
    /// ``MetricKitPayloadsMirror/Snapshot`` while its session is open. A crash's diagnostic, which
    /// MetricKit delivers on a later launch, so reaches the next session. Under a grant policy
    /// only a session whose grant lists ``MetricKitPayloadsMirror/pluginID`` is served them.
    ///
    /// Making it subscribes to `MXMetricManager`; nothing is kept before. Where MetricKit doesn't
    /// exist, nothing arrives.
    ///
    /// ```swift
    /// receiver.enable(.metricKitPayloads(sessions: sessions))
    /// ```
    ///
    /// - Parameters:
    ///   - sessions: The receiver's sessions, which the snapshot follows.
    ///   - directory: Where the payloads are kept, in the app's own storage;
    ///     ``MetricKitPayloadsMirror/defaultDirectory`` unless given.
    ///   - redaction: The rules every payload is redacted by before it is kept;
    ///     ``MetricKitRedaction/standard`` unless given.
    ///   - capacity: The most payloads kept, the latest periods.
    /// - Returns: The capability, under ``MetricKitPayloadsMirror/pluginID``.
    /// - Precondition: `capacity` is at least 1.
    static func metricKitPayloads(
        sessions: DebugDrawerSessions,
        directory: URL = MetricKitPayloadsMirror.defaultDirectory,
        redaction: MetricKitRedaction = .standard,
        capacity: Int = MetricKitPayloadsMirror.defaultCapacity
    ) -> Self {
        #if canImport(MetricKit)
            let source: (any MetricKitPayloadSource)? = MetricManagerPayloadSource()
        #else
            let source: (any MetricKitPayloadSource)? = nil
        #endif
        let mirror = MetricKitPayloadsMirror(sessions: sessions, directory: directory, redaction: redaction, capacity: capacity, source: source)
        return .model(mirror, id: MetricKitPayloadsMirror.pluginID, scope: .persistent)
    }
}
