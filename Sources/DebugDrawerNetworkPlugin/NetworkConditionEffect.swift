import Foundation

/// What a conditioning profile did to a request: which profile, the latency it added, the
/// bandwidth it capped the response at, and the failure it ended the request with, if any.
public struct NetworkConditionEffect: Hashable, Sendable {
    /// The name of the profile that applied.
    public let profileName: String
    /// How long the request waited before it was answered or sent.
    public let latency: Duration
    /// The most bytes a second the response's body arrived at, or `nil` for no cap.
    public let bandwidth: Int?
    /// How the profile failed the request, or `nil` when it let the request through.
    public let failure: NetworkConditionProfile.Failure?

    /// The effect as the log shows it: "Delayed 2,000 ms · 50 KB/s · Failed: timeout", each
    /// part only when the profile did it.
    var summary: String {
        var parts: [String] = []
        if latency > .zero {
            parts.append("Delayed \(latency.millisecondsText)")
        }
        if let bandwidth {
            parts.append("Capped at \(bandwidth.bandwidthText)")
        }
        if let failure {
            parts.append("Failed: \(failure.phrase)")
        }
        return parts.isEmpty ? "No effect" : parts.joined(separator: " · ")
    }
}

extension Duration {
    /// The duration in whole milliseconds, grouped: "2,000 ms".
    var millisecondsText: String {
        "\(milliseconds.formatted()) ms"
    }
}

extension Int {
    /// A bandwidth in bytes a second, in kilobytes (of 1,000 bytes) to one decimal place:
    /// "97.5 KB/s"; under a kilobyte, in bytes: "500 B/s".
    var bandwidthText: String {
        guard self >= 1000 else { return "\(self) B/s" }
        let kilobytes = Double(self) / 1000
        return "\(kilobytes.formatted(.number.precision(.fractionLength(0 ... 1)))) KB/s"
    }
}

extension NetworkConditionProfile.Failure {
    /// The failure as the drawer names it.
    var title: String {
        switch self {
        case .timedOut: "Timeout"
        case .notConnectedToInternet: "No Connection"
        case .internalServerError: "HTTP 500"
        }
    }

    /// The failure in a phrase after "Failed:".
    var phrase: String {
        switch self {
        case .timedOut: "timeout"
        case .notConnectedToInternet: "no connection"
        case .internalServerError: "HTTP 500"
        }
    }
}
