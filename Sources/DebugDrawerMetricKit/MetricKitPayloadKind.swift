/// Which of MetricKit's two payloads one is.
///
/// Real in every build: `MetricKitPayloads.add(json:kind:)` takes it, and so does a payload the
/// receiver's capability serves a sidecar (``MetricKitPayloadsMirror/Payload``).
public enum MetricKitPayloadKind: String, Codable, Sendable {
    /// An `MXMetricPayload`: a day's metrics (launch times, hangs, disk writes, memory, energy).
    case metrics
    /// An `MXDiagnosticPayload`: crashes, hangs, CPU and disk-write exceptions, slow launches.
    case diagnostics
}
