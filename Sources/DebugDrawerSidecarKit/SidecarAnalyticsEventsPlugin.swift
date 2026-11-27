import DebugDrawer
import DebugDrawerAnalytics
import Foundation
import SwiftUI

// The sidecar's half of analytics mirroring (DD-124): the events the app records while the
// session is open (`AnalyticsEventsMirror`, in DebugDrawerAnalytics), newest first, redacted in the
// app before they left it, each with its properties, and Clear. It ships in the kit, as the events
// describe themselves, so every sidecar would draw the same list. Under a grant policy a session
// whose grant doesn't list the mirror gets its session ID and no events; the empty state says so.

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// The analytics events the app records during the session
        /// (`DebugDrawerReceiverCapability.analyticsEvents(sessions:redaction:capacity:)`), newest
        /// first and redacted in the app, with Clear.
        @MainActor public static var analyticsEvents: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: AnalyticsEventsMirror.pluginID, title: "Analytics", icon: "chart.bar",
                snapshot: AnalyticsEventsMirror.Snapshot.self, command: AnalyticsEventsMirror.Command.self
            ) { transport in
                AnalyticsEventsSidecarPlugin(transport: transport)
            }
            .collectedWhileRunning()
        }
    }

    /// The app's mirrored analytics events, shown in the sidecar.
    struct AnalyticsEventsSidecarPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<AnalyticsEventsMirror.Snapshot, AnalyticsEventsMirror.Command>
        let title = "Analytics"
        let icon = "chart.bar"

        var body: some View {
            AnalyticsEventsTransportView(transport: transport)
        }
    }

    /// The events over the capability's snapshot, sending what the view asks.
    struct AnalyticsEventsTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<AnalyticsEventsMirror.Snapshot, AnalyticsEventsMirror.Command>

        var body: some View {
            AnalyticsEventsSidecarView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// The session's events, newest first, and Clear; or why there are none. A function of the
    /// snapshot and the send action.
    struct AnalyticsEventsSidecarView: View {
        let snapshot: AnalyticsEventsMirror.Snapshot
        let send: (AnalyticsEventsMirror.Command) -> Void

        var body: some View {
            if snapshot.events.isEmpty {
                DebugDrawerEmptyState("No Events", systemImage: "chart.bar") {
                    Text(
                        snapshot.sessionID == nil
                            ? "The app mirrors the events it records only while a session is open."
                            : "Events the app records while the session is open show here."
                    )
                }
            } else {
                DebugDrawerSection("Events") {
                    ForEach(snapshot.events.reversed()) { event in
                        DebugDrawerRow(event.name) {
                            ForEach(event.properties.keys.sorted(), id: \.self) { key in
                                Text("\(key): \(event.properties[key]?.summary ?? "")")
                            }
                            if let source = event.source {
                                Text(source)
                            }
                        } accessory: {
                            Text(event.timestamp, style: .time)
                                .debugDrawerFont(.value)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("AnalyticsEvent-\(event.id)")
                    }
                } footer: {
                    Text("Redacted in the app before they left it.")
                }
                DebugDrawerActionRow {
                    EmptyView()
                } trailing: {
                    Button("Clear", role: .destructive) { send(.clear) }
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel("Clear")
                        .accessibilityHint("Empties the session's list of events")
                }
            }
        }
    }

    extension AnalyticsValue {
        /// The value as a property line shows it: text quoted, a list and an object as JSON-like
        /// text.
        fileprivate var summary: String {
            switch self {
            case let .string(text): "\"\(text)\""
            case let .int(number): "\(number)"
            case let .double(number): number.formatted()
            case let .bool(value): value ? "true" : "false"
            case let .date(date): date.formatted(.iso8601)
            case .null: "null"
            case let .array(values): "[\(values.map(\.summary).joined(separator: ", "))]"
            case let .object(values): "{\(values.keys.sorted().map { "\($0): \(values[$0]?.summary ?? "")" }.joined(separator: ", "))}"
            }
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The analytics events the app records during the session; release builds show nothing.
        @MainActor public static var analyticsEvents: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: AnalyticsEventsMirror.pluginID, title: "Analytics", icon: "chart.bar",
                snapshot: AnalyticsEventsMirror.Snapshot.self, command: AnalyticsEventsMirror.Command.self
            ) { _ in
                AnalyticsEventsSidecarPlugin()
            }
        }
    }

    /// Draws nothing.
    struct AnalyticsEventsSidecarPlugin: DebugDrawerPlugin {
        let title = "Analytics"
        let icon = "chart.bar"

        var body: some View {
            EmptyView()
        }
    }
#endif
