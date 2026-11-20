import DebugDrawer
import DebugDrawerSidecarKit
import SwiftUI

extension DebugDrawerSidecarPlugin {
    /// The host's log subsystems (`DebugDrawerReceiverCapability.logLevels`), each raised to a more
    /// verbose level for the session.
    @MainActor static var logLevels: DebugDrawerSidecarPlugin {
        DebugDrawerSidecarPlugin(
            id: DebugDrawerLogLevels.pluginID, title: "Log Levels", icon: "text.alignleft",
            snapshot: DebugDrawerLogLevels.Snapshot.self, command: DebugDrawerLogLevels.Command.self
        ) { transport in
            LogLevelsPlugin(transport: transport)
        }
    }
}

/// The host's log subsystems: a picker of levels for each, which are raised, and Reset All.
struct LogLevelsPlugin: DebugDrawerPlugin {
    let transport: DebugDrawerPluginTransport<DebugDrawerLogLevels.Snapshot, DebugDrawerLogLevels.Command>
    let title = "Log Levels"
    let icon = "text.alignleft"

    var body: some View {
        LogLevelsView(transport: transport)
    }
}

private struct LogLevelsView: View {
    @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerLogLevels.Snapshot, DebugDrawerLogLevels.Command>

    var body: some View {
        DebugDrawerSection("Subsystems") {
            ForEach(transport.snapshot.subsystems, id: \.name) { subsystem in
                DebugDrawerRow(subsystem.name) {
                    Picker(subsystem.name, selection: Binding(
                        get: { subsystem.level },
                        set: { transport.send(.setLevel(subsystem: subsystem.name, level: $0)) }
                    )) {
                        ForEach(subsystem.levels, id: \.self) { level in
                            Text(level).tag(level)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel(subsystem.name)
                }
            }
        } footer: {
            Text(
                transport.snapshot.raisedSubsystems.isEmpty
                    ? "No subsystem raised"
                    : "Raised until the session ends: \(transport.snapshot.raisedSubsystems.joined(separator: ", "))"
            )
        }
        DebugDrawerActionRow {
            Button("Reset All Levels") { transport.send(.resetAll) }
        }
    }
}
