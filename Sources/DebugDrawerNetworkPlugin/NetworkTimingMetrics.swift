#if DEBUG
    import Foundation
    import SwiftUI

    // MARK: - Timing model

    /// The phases of one HTTP transaction, taken from `URLSessionTaskTransactionMetrics`.
    public struct NetworkTimingMetrics: Sendable, Equatable {
        public struct Phase: Sendable, Equatable, Identifiable {
            public enum Kind: String, CaseIterable, Sendable {
                case dns = "DNS"
                case connect = "Connect"
                case tls = "TLS"
                case request = "Request"
                case timeToFirstByte = "TTFB"
                case response = "Response"
            }

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

        init(timestamps t: Timestamps, protocolName: String?, isReusedConnection: Bool, isCacheHit: Bool) {
            let all = [t.fetchStart, t.domainLookupStart, t.domainLookupEnd, t.connectStart,
                       t.secureConnectionStart, t.secureConnectionEnd, t.connectEnd,
                       t.requestStart, t.requestEnd, t.responseStart, t.responseEnd]
            let origin = t.fetchStart ?? all.compactMap { $0 }.min()

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
                    phase(.dns, t.domainLookupStart, t.domainLookupEnd),
                    phase(.connect, t.connectStart, t.secureConnectionStart ?? t.connectEnd),
                    phase(.tls, t.secureConnectionStart, t.secureConnectionEnd),
                    phase(.request, t.requestStart, t.requestEnd),
                    phase(.timeToFirstByte, t.requestEnd, t.responseStart),
                    phase(.response, t.responseStart, t.responseEnd),
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

    // MARK: - Waterfall view

    struct NetworkTimingView: View {
        let metrics: NetworkTimingMetrics

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                let total = metrics.total
                ForEach(metrics.phases) { phase in
                    HStack(spacing: 4) {
                        Text(phase.kind.rawValue)
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 56, alignment: .leading)
                        GeometryReader { geo in
                            let scale = total > 0 ? geo.size.width / total : 0
                            RoundedRectangle(cornerRadius: 1)
                                .fill(color(for: phase.kind))
                                .frame(width: max(1, phase.duration * scale))
                                .offset(x: phase.start * scale)
                        }
                        .frame(height: 6)
                        Text(NetworkTimingMetrics.label(for: phase.duration))
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .frame(width: 48, alignment: .trailing)
                    }
                }

                HStack(spacing: 10) {
                    Text("Protocol: \(metrics.protocolName ?? "—")")
                    Text("Reused connection: \(metrics.isReusedConnection ? "Yes" : "No")")
                    Text("Cache hit: \(metrics.isCacheHit ? "Yes" : "No")")
                }
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.top, 2)
            }
            .padding(4)
        }

        private func color(for kind: NetworkTimingMetrics.Phase.Kind) -> Color {
            switch kind {
            case .dns: .teal
            case .connect: .orange
            case .tls: .purple
            case .request: .blue
            case .timeToFirstByte: .green
            case .response: .cyan
            }
        }
    }
#endif
