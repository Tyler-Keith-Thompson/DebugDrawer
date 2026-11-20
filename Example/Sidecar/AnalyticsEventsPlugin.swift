import DebugDrawer
import DebugDrawerAnalytics
import DebugDrawerSidecarKit
import SwiftUI

extension DebugDrawerSidecarPlugin {
    /// The analytics events the host records during the session (`DebugDrawerReceiverCapability.analyticsEvents`).
    @MainActor static var analyticsEvents: DebugDrawerSidecarPlugin {
        DebugDrawerSidecarPlugin(
            id: AnalyticsEventsMirror.pluginID, title: "Analytics", icon: "chart.bar",
            snapshot: AnalyticsEventsMirror.Snapshot.self, command: AnalyticsEventsMirror.Command.self
        ) { transport in
            AnalyticsEventsPlugin(transport: transport)
        }
    }
}

/// The session's events, newest first, redacted in the host before they left it.
struct AnalyticsEventsPlugin: DebugDrawerPlugin {
    let transport: DebugDrawerPluginTransport<AnalyticsEventsMirror.Snapshot, AnalyticsEventsMirror.Command>
    let title = "Analytics"
    let icon = "chart.bar"

    var body: some View {
        AnalyticsEventsView(transport: transport)
    }
}

private struct AnalyticsEventsView: View {
    @ObservedObject var transport: DebugDrawerPluginTransport<AnalyticsEventsMirror.Snapshot, AnalyticsEventsMirror.Command>

    var body: some View {
        if transport.snapshot.events.isEmpty {
            DebugDrawerEmptyState("No Events", systemImage: "chart.bar") {
                Text("Events the app records while the session is open show here.")
            }
        } else {
            DebugDrawerSection("Events") {
                ForEach(transport.snapshot.events.reversed()) { event in
                    DebugDrawerRow(event.name) {
                        Text(event.properties.keys.sorted().map { "\($0): \(event.properties[$0].map(String.init(describing:)) ?? "")" }
                            .joined(separator: ", "))
                    } accessory: {
                        Text(event.timestamp, style: .time)
                            .debugDrawerFont(.value)
                    }
                }
            }
        }
        DebugDrawerActionRow {
            Button("Clear") { transport.send(.clear) }
        }
    }
}
