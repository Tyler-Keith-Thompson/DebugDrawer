import DebugDrawer
import SwiftUI

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
