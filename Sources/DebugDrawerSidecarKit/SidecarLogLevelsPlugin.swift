import DebugDrawer
import Foundation
import SwiftUI

// The sidecar's half of log level elevation (DD-111): the subsystems the app's adapter lists
// (`DebugDrawerLogLevels`, in the receiver), each with a picker of the levels it takes, Reset for a
// raised one, and Reset All Levels while any is. It ships in the kit, as each subsystem lists its
// own levels in the logger's names, so every sidecar would draw the same pickers. The raised lines
// go to the app logger's own destinations; the plugin shows no line (Diagnostics does, once the app
// forwards them to its capture).

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// The log subsystems the app's adapter lists (`DebugDrawerReceiverCapability.logLevels(_:)`),
        /// each raised to a more verbose level for the session, with Reset and Reset All Levels.
        @MainActor public static var logLevels: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerLogLevels.pluginID, title: "Log Levels", icon: "text.alignleft",
                snapshot: DebugDrawerLogLevels.Snapshot.self, command: DebugDrawerLogLevels.Command.self
            ) { transport in
                LogLevelsSidecarPlugin(transport: transport)
            }
        }
    }

    /// The app's log subsystems, raised from the sidecar.
    struct LogLevelsSidecarPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<DebugDrawerLogLevels.Snapshot, DebugDrawerLogLevels.Command>
        let title = "Log Levels"
        let icon = "text.alignleft"

        var body: some View {
            LogLevelsTransportView(transport: transport)
        }
    }

    /// The subsystems over the capability's snapshot, sending what the view asks.
    struct LogLevelsTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerLogLevels.Snapshot, DebugDrawerLogLevels.Command>

        var body: some View {
            LogLevelsView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// Each subsystem with its level picker, and Reset All Levels while any is raised. A function
    /// of the snapshot and the send action.
    struct LogLevelsView: View {
        let snapshot: DebugDrawerLogLevels.Snapshot
        let send: (DebugDrawerLogLevels.Command) -> Void

        var body: some View {
            if snapshot.subsystems.isEmpty {
                DebugDrawerEmptyState("No Subsystems", systemImage: "text.alignleft") {
                    Text("The app's adapter lists no subsystem a sidecar may raise.")
                }
            } else {
                DebugDrawerSection("Subsystems") {
                    ForEach(snapshot.subsystems, id: \.name) { subsystem in
                        LogSubsystemRow(subsystem: subsystem, isRaised: snapshot.raisedSubsystems.contains(subsystem.name), send: send)
                    }
                    if !snapshot.raisedSubsystems.isEmpty {
                        DebugDrawerActionRow {
                            Button("Reset All Levels") { send(.resetAll) }
                                .debugDrawerButtonStyle(.secondary)
                                .accessibilityLabel("Reset All Levels")
                                .accessibilityHint("Every subsystem logs at the app's own level again")
                        }
                    }
                } footer: {
                    Text(
                        snapshot.raisedSubsystems.isEmpty
                            ? "No subsystem raised."
                            : "Raised until the session ends: \(snapshot.raisedSubsystems.joined(separator: ", "))"
                    )
                }
            }
        }
    }

    /// One subsystem: its name, a picker of its levels, and Reset once raised.
    struct LogSubsystemRow: View {
        let subsystem: DebugDrawerLogSubsystem
        let isRaised: Bool
        let send: (DebugDrawerLogLevels.Command) -> Void

        var body: some View {
            DebugDrawerRow(subsystem.name) {
                if isRaised {
                    Text("Raised")
                        .debugDrawerForegroundStyle(.accent)
                    Button("Reset") { send(.reset(subsystem: subsystem.name)) }
                        .debugDrawerButtonStyle(.secondary)
                        .accessibilityLabel("Reset \(subsystem.name)")
                        .accessibilityHint("The subsystem logs at the app's own level again")
                }
            } accessory: {
                Picker(subsystem.name, selection: Binding {
                    subsystem.level
                } set: {
                    send(.setLevel(subsystem: subsystem.name, level: $0))
                }) {
                    ForEach(subsystem.levels, id: \.self) { level in
                        Text(level).tag(level)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(subsystem.name)
            }
            .accessibilityIdentifier("LogSubsystem-\(subsystem.name)")
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The log subsystems the app's adapter lists; release builds show nothing.
        @MainActor public static var logLevels: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerLogLevels.pluginID, title: "Log Levels", icon: "text.alignleft",
                snapshot: DebugDrawerLogLevels.Snapshot.self, command: DebugDrawerLogLevels.Command.self
            ) { _ in
                LogLevelsSidecarPlugin()
            }
        }
    }

    /// Draws nothing.
    struct LogLevelsSidecarPlugin: DebugDrawerPlugin {
        let title = "Log Levels"
        let icon = "text.alignleft"

        var body: some View {
            EmptyView()
        }
    }
#endif
