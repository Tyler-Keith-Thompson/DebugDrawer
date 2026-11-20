import DebugDrawer
import DebugDrawerSidecarKit
import SwiftUI

extension DebugDrawerSidecarPlugin {
    /// The host's experiments (`DebugDrawerReceiverCapability.experimentOverrides`), each forced
    /// into a variant for the session.
    @MainActor static var experimentOverrides: DebugDrawerSidecarPlugin {
        DebugDrawerSidecarPlugin(
            id: DebugDrawerExperimentOverrides.pluginID, title: "Experiments", icon: "flask",
            snapshot: DebugDrawerExperimentOverrides.Snapshot.self, command: DebugDrawerExperimentOverrides.Command.self
        ) { transport in
            ExperimentOverridesPlugin(transport: transport)
        }
    }
}

/// The host's experiments: a picker of variants for each, whether the app is excluded from their
/// analytics, and Clear All.
struct ExperimentOverridesPlugin: DebugDrawerPlugin {
    let transport: DebugDrawerPluginTransport<DebugDrawerExperimentOverrides.Snapshot, DebugDrawerExperimentOverrides.Command>
    let title = "Experiments"
    let icon = "flask"

    var body: some View {
        ExperimentOverridesView(transport: transport)
    }
}

private struct ExperimentOverridesView: View {
    @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerExperimentOverrides.Snapshot, DebugDrawerExperimentOverrides.Command>

    var body: some View {
        DebugDrawerSection("Experiments") {
            ForEach(transport.snapshot.experiments, id: \.key) { experiment in
                DebugDrawerRow(experiment.key) {
                    Picker(experiment.key, selection: Binding(
                        get: { experiment.assignedVariant ?? "" },
                        set: { transport.send(.setOverride(experiment: experiment.key, variant: $0)) }
                    )) {
                        if experiment.assignedVariant == nil {
                            Text("Not enrolled").tag("")
                        }
                        ForEach(experiment.variants, id: \.self) { variant in
                            Text(variant).tag(variant)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel(experiment.key)
                }
            }
        } footer: {
            Text(
                transport.snapshot.overriddenKeys.isEmpty
                    ? "No experiment overridden"
                    : "Overridden, so excluded from analytics: \(transport.snapshot.overriddenKeys.joined(separator: ", "))"
            )
        }
        DebugDrawerActionRow {
            Button("Clear All Overrides") { transport.send(.clearAllOverrides) }
        }
    }
}
