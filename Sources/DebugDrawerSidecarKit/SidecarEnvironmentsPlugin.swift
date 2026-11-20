import DebugDrawer
import Foundation
import SwiftUI

// The sidecar's half of environment switching (DD-120): the environments the app lists
// (`DebugDrawerEnvironments`, in the receiver), the active one marked, a Switch button for each
// other one, and a warning that says what a switch does, as the capability is high risk. It ships
// in the kit, beside Scenarios and Auth, as the capability describes itself, so every sidecar would
// draw the same list. A switch carries an environment's ID and nothing else: the plugin has no
// field to type an address in, and the snapshot holds none to show. It doesn't open the app: a
// switch waits in the store and lands as the app comes to the foreground, where the session
// indicator then names the backend.

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// The environments the app lists (`DebugDrawerReceiverCapability.environments(_:)`), the
        /// active one marked, a Switch button for each other one, and Reset to Default, under a
        /// warning that a switch sends the app's traffic to that backend until the session ends.
        @MainActor public static var environments: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerEnvironments.pluginID, title: "Environment", icon: "server.rack",
                snapshot: DebugDrawerEnvironments.Snapshot.self, command: DebugDrawerEnvironments.Command.self
            ) { transport in
                EnvironmentsPlugin(transport: transport)
            }
        }
    }

    /// The app's environments, switched from the sidecar.
    struct EnvironmentsPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<DebugDrawerEnvironments.Snapshot, DebugDrawerEnvironments.Command>
        let title = "Environment"
        let icon = "server.rack"

        var body: some View {
            EnvironmentsTransportView(transport: transport)
        }
    }

    /// The environments over the capability's snapshot, sending what the view asks.
    struct EnvironmentsTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerEnvironments.Snapshot, DebugDrawerEnvironments.Command>

        var body: some View {
            EnvironmentsView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// The warning, each environment with the active one marked and a Switch button for the
    /// others, and Reset to Default while switched. A function of the snapshot and the send
    /// action.
    struct EnvironmentsView: View {
        let snapshot: DebugDrawerEnvironments.Snapshot
        let send: (DebugDrawerEnvironments.Command) -> Void

        var body: some View {
            DebugDrawerSection("High Risk") {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    DebugDrawerIssueGlyph(.warning)
                        .accessibilityHidden(true)
                    Text(
                        "Switching sends the app's traffic, its signed-in account's included, to that backend until the session ends."
                    )
                    .debugDrawerFont(.label)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .debugDrawerRowPadding()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("High risk: switching sends the app's traffic to that backend until the session ends")
                .accessibilityIdentifier("EnvironmentsRiskWarning")
            }
            DebugDrawerSection("Environments") {
                ForEach(snapshot.environments) { environment in
                    EnvironmentRow(
                        environment: environment,
                        isActive: environment.id == snapshot.activeEnvironment,
                        isDefault: environment.id == snapshot.defaultEnvironment
                    ) {
                        send(.activate(environment: environment.id))
                    }
                }
                if snapshot.isSwitched {
                    DebugDrawerActionRow {
                        Button("Reset to Default") { send(.reset) }
                            .debugDrawerButtonStyle(.secondary)
                            .accessibilityLabel("Reset to Default")
                    }
                }
            }
        }
    }

    /// One environment: its title and summary, marked Active or Default, and a Switch button
    /// unless it is the active one.
    struct EnvironmentRow: View {
        let environment: DebugDrawerEnvironment
        let isActive: Bool
        let isDefault: Bool
        let activate: () -> Void

        var body: some View {
            DebugDrawerRow(environment.title, systemImage: isActive ? "checkmark.circle.fill" : "circle") {
                if !environment.summary.isEmpty {
                    Text(environment.summary)
                }
                if isDefault {
                    Text("Default")
                }
            } accessory: {
                if isActive {
                    Text("Active")
                        .debugDrawerForegroundStyle(.accent)
                } else {
                    Button("Switch", action: activate)
                        .debugDrawerButtonStyle(.primary)
                        .accessibilityLabel("Switch to \(environment.title)")
                }
            }
            .accessibilityIdentifier("Environment-\(environment.id)")
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The environments the app lists; release builds show nothing.
        @MainActor public static var environments: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerEnvironments.pluginID, title: "Environment", icon: "server.rack",
                snapshot: DebugDrawerEnvironments.Snapshot.self, command: DebugDrawerEnvironments.Command.self
            ) { _ in
                EnvironmentsPlugin()
            }
        }
    }

    /// Draws nothing.
    struct EnvironmentsPlugin: DebugDrawerPlugin {
        let title = "Environment"
        let icon = "server.rack"

        var body: some View {
            EmptyView()
        }
    }
#endif
