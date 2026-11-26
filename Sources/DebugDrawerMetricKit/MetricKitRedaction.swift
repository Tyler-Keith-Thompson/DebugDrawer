import Foundation

// MetricKit's payloads are the system's measurements, in a schema the system fixes: numbers,
// histograms, stack frames (binary, UUID, offset, address) and system text (the OS, the device,
// a termination reason). The one place an app's own data lands in them is an Objective-C
// exception that crashed the app: its message is composed from the app's format string and the
// values formatted into it, which may be a user's. So the redaction masks by key, at any depth:
// the composed message and the arguments, keeping the format string, which is the code's own
// constant text and says what went wrong. Rejected: an allow-list of MetricKit's keys (every key
// a new OS adds would vanish from the sidecar, and the schema is the system's, not the app's);
// value patterns as the analytics capability has (no key here holds free text an app wrote but
// the two masked); no redaction (an exception's message can hold an email address or a token).

/// Which values of a MetricKit payload's JSON are masked before the payload is kept for a sidecar:
/// those under the keys it names, at any depth.
///
/// ```swift
/// try receiver.enable(.metricKitPayloads(sessions: sessions, redaction: .standard.adding(keys: ["virtualMemoryRegionInfo"])))
/// ```
public struct MetricKitRedaction: Equatable, Sendable {
    /// What a masked value becomes.
    public static let mask = "[REDACTED]"

    /// The keys whose values are masked, matched exactly, as MetricKit spells them.
    public let keys: Set<String>

    /// Rules that mask the values under `keys`.
    ///
    /// - Parameter keys: The JSON keys whose values are masked, at any depth, whatever the value
    ///   (an object or array under one is masked whole).
    public init(keys: Set<String>) {
        self.keys = keys
    }

    /// The default: an Objective-C exception's `composedMessage` and its `arguments`, the parts
    /// of a crash's reason the app's values are formatted into. Its `formatString` is kept.
    public static let standard = MetricKitRedaction(keys: ["composedMessage", "arguments"])

    /// No rules: every payload is kept as MetricKit wrote it.
    public static let none = MetricKitRedaction(keys: [])

    /// These rules, masking `additional` too.
    ///
    /// - Parameter additional: More JSON keys whose values are masked.
    /// - Returns: The combined rules.
    public func adding(keys additional: Set<String>) -> MetricKitRedaction {
        MetricKitRedaction(keys: keys.union(additional))
    }

    /// `json` with the values under ``keys`` masked, compact with its keys sorted, or `nil` when it
    /// isn't a JSON object.
    ///
    /// - Parameter json: A payload's `jsonRepresentation()`.
    /// - Returns: The redacted JSON object.
    func redact(_ json: Data) -> Data? {
        guard let object = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else { return nil }
        return try? JSONSerialization.data(withJSONObject: masked(object), options: [.sortedKeys, .withoutEscapingSlashes])
    }

    /// `value` with every value under one of ``keys`` replaced by ``mask``.
    private func masked(_ value: Any) -> Any {
        switch value {
        case let object as [String: Any]:
            object.reduce(into: [String: Any]()) { result, entry in
                result[entry.key] = keys.contains(entry.key) ? Self.mask : masked(entry.value)
            }
        case let array as [Any]:
            array.map(masked)
        default:
            value
        }
    }
}
