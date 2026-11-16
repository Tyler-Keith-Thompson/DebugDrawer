/// Which of MetricKit's two payloads one is.
///
/// The type exists in every build, so ``MetricKitPayloads/add(json:kind:)`` compiles unchanged in
/// release.
public enum MetricKitPayloadKind: String, Codable, Sendable {
    /// An `MXMetricPayload`: a day's metrics (launch times, hangs, disk writes, memory, energy).
    case metrics
    /// An `MXDiagnosticPayload`: crashes, hangs, CPU and disk-write exceptions, slow launches.
    case diagnostics
}
