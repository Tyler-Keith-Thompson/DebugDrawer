import DebugDrawer
import Foundation
import SwiftUI

// MARK: - Timing model

/// The phases of one HTTP transaction, taken from `URLSessionTaskTransactionMetrics`.
public struct NetworkTimingMetrics: Sendable, Equatable {
    public struct Phase: Sendable, Equatable, Identifiable {
        public let kind: Kind
        /// Seconds from the start of the fetch to the start of this phase.
        public let start: TimeInterval
        public let duration: TimeInterval
        public var id: Kind { kind }
    }

    /// The timestamps of a transaction, as `URLSessionTaskTransactionMetrics` reports them.
    struct Timestamps: Sendable {
        var fetchStart: Date?
        var domainLookupStart: Date?
        var domainLookupEnd: Date?
        var connectStart: Date?
        var secureConnectionStart: Date?
        var secureConnectionEnd: Date?
        var connectEnd: Date?
        var requestStart: Date?
        var requestEnd: Date?
        var responseStart: Date?
        var responseEnd: Date?
    }

    /// Only the phases whose start and end were both reported, in order.
    public let phases: [Phase]
    /// The ALPN protocol, such as `h2`, `h3` or `http/1.1`.
    public let protocolName: String?
    public let isReusedConnection: Bool
    /// The response came from the local cache (`resourceFetchType == .localCache`).
    public let isCacheHit: Bool

    /// The end of the last phase, measured from the start of the fetch.
    public var total: TimeInterval {
        phases.map { $0.start + $0.duration }.max() ?? 0
    }

    public init(phases: [Phase], protocolName: String?, isReusedConnection: Bool, isCacheHit: Bool) {
        self.phases = phases
        self.protocolName = protocolName
        self.isReusedConnection = isReusedConnection
        self.isCacheHit = isCacheHit
    }

    init(timestamps: Timestamps, protocolName: String?, isReusedConnection: Bool, isCacheHit: Bool) {
        let all = [timestamps.fetchStart, timestamps.domainLookupStart, timestamps.domainLookupEnd, timestamps.connectStart,
                   timestamps.secureConnectionStart, timestamps.secureConnectionEnd, timestamps.connectEnd,
                   timestamps.requestStart, timestamps.requestEnd, timestamps.responseStart, timestamps.responseEnd]
        let origin = timestamps.fetchStart ?? all.compactMap { $0 }.min()

        func phase(_ kind: Phase.Kind, _ start: Date?, _ end: Date?) -> Phase? {
            guard let origin, let start, let end else { return nil }
            return Phase(kind: kind,
                         start: max(0, start.timeIntervalSince(origin)),
                         duration: max(0, end.timeIntervalSince(start)))
        }

        // connectStart…connectEnd includes the TLS handshake; end the connect phase
        // where TLS starts so the two don't overlap.
        self.init(
            phases: [
                phase(.dns, timestamps.domainLookupStart, timestamps.domainLookupEnd),
                phase(.connect, timestamps.connectStart, timestamps.secureConnectionStart ?? timestamps.connectEnd),
                phase(.tls, timestamps.secureConnectionStart, timestamps.secureConnectionEnd),
                phase(.request, timestamps.requestStart, timestamps.requestEnd),
                phase(.timeToFirstByte, timestamps.requestEnd, timestamps.responseStart),
                phase(.response, timestamps.responseStart, timestamps.responseEnd)
            ].compactMap { $0 },
            protocolName: protocolName,
            isReusedConnection: isReusedConnection,
            isCacheHit: isCacheHit
        )
    }

    init(_ transaction: URLSessionTaskTransactionMetrics) {
        self.init(
            timestamps: Timestamps(
                fetchStart: transaction.fetchStartDate,
                domainLookupStart: transaction.domainLookupStartDate,
                domainLookupEnd: transaction.domainLookupEndDate,
                connectStart: transaction.connectStartDate,
                secureConnectionStart: transaction.secureConnectionStartDate,
                secureConnectionEnd: transaction.secureConnectionEndDate,
                connectEnd: transaction.connectEndDate,
                requestStart: transaction.requestStartDate,
                requestEnd: transaction.requestEndDate,
                responseStart: transaction.responseStartDate,
                responseEnd: transaction.responseEndDate
            ),
            protocolName: transaction.networkProtocolName,
            isReusedConnection: transaction.isReusedConnection,
            isCacheHit: transaction.resourceFetchType == .localCache
        )
    }

    /// The last transaction of the task: the one that produced the response the app saw.
    init?(_ metrics: URLSessionTaskMetrics) {
        guard let last = metrics.transactionMetrics.last else { return nil }
        self.init(last)
    }

    static func label(for duration: TimeInterval) -> String {
        if duration < 1 { return String(format: "%.1fms", duration * 1000) }
        return String(format: "%.2fs", duration)
    }
}

// Declared in an extension so the type nests one level deep, not two.
extension NetworkTimingMetrics.Phase {
    public enum Kind: String, CaseIterable, Sendable {
        case dns = "DNS"
        case connect = "Connect"
        case tls = "TLS"
        case request = "Request"
        case timeToFirstByte = "TTFB"
        case response = "Response"
    }
}

// MARK: - Timing view

/// A request's phases as gauges, as Xcode's debug gauges show a measure: each phase's bar
/// filled by its share of the whole request, then how the connection was made.
struct NetworkTimingView: View {
    let metrics: NetworkTimingMetrics

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(metrics.phases) { phase in
                DebugDrawerGaugeRow(
                    phase.kind.rawValue,
                    value: NetworkTimingMetrics.label(for: phase.duration),
                    fraction: metrics.total > 0 ? phase.duration / metrics.total : 0
                )
            }
            DebugDrawerKeyValueRow("Protocol", value: metrics.protocolName ?? "—")
            DebugDrawerKeyValueRow("Reused", value: metrics.isReusedConnection ? "Yes" : "No")
            DebugDrawerKeyValueRow("Cache hit", value: metrics.isCacheHit ? "Yes" : "No")
        }
    }
}
