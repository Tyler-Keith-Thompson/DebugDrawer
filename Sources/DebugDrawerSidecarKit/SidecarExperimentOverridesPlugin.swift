import DebugDrawer
import Foundation
import SwiftUI

// The sidecar's half of experiment overrides (DD-109): the experiments the app's adapter lists
// (`DebugDrawerExperimentOverrides`, in the receiver), each with a picker of its variants, Clear
// for a forced one, and Clear All Overrides while any is, under a note that a forced experiment
// excludes the device from its analytics. It ships in the kit, as each experiment lists its own
// variants, so every sidecar would draw the same pickers. "Not enrolled" is shown for an
// experiment the app hasn't bucketed, and is no variant to send.

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// The experiments the app's adapter lists (`DebugDrawerReceiverCapability.experimentOverrides(_:scope:)`),
        /// each forced into a variant for the session, with Clear and Clear All Overrides.
        @MainActor public static var experimentOverrides: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerExperimentOverrides.pluginID, title: "Experiments", icon: "flask",
                snapshot: DebugDrawerExperimentOverrides.Snapshot.self, command: DebugDrawerExperimentOverrides.Command.self
            ) { transport in
                ExperimentOverridesSidecarPlugin(transport: transport)
            }
        }
    }

    /// The app's experiments, forced from the sidecar.
    struct ExperimentOverridesSidecarPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<DebugDrawerExperimentOverrides.Snapshot, DebugDrawerExperimentOverrides.Command>
        let title = "Experiments"
        let icon = "flask"

        var body: some View {
            ExperimentOverridesTransportView(transport: transport)
        }
    }

    /// The experiments over the capability's snapshot, sending what the view asks.
    struct ExperimentOverridesTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerExperimentOverrides.Snapshot, DebugDrawerExperimentOverrides.Command>

        var body: some View {
            ExperimentOverridesView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// Each experiment with its variant picker, and Clear All Overrides while any is forced. A
    /// function of the snapshot and the send action.
    struct ExperimentOverridesView: View {
        let snapshot: DebugDrawerExperimentOverrides.Snapshot
        let send: (DebugDrawerExperimentOverrides.Command) -> Void

        var body: some View {
            if snapshot.experiments.isEmpty {
                DebugDrawerEmptyState("No Experiments", systemImage: "flask") {
                    Text("The app's adapter lists no experiment a sidecar may force.")
                }
            } else {
                DebugDrawerSection("Experiments") {
                    ForEach(snapshot.experiments, id: \.key) { experiment in
                        ExperimentOverrideRow(
                            experiment: experiment, isOverridden: snapshot.overriddenKeys.contains(experiment.key), send: send
                        )
                    }
                    if !snapshot.overriddenKeys.isEmpty {
                        DebugDrawerActionRow {
                            Button("Clear All Overrides") { send(.clearAllOverrides) }
                                .debugDrawerButtonStyle(.secondary)
                                .accessibilityLabel("Clear All Overrides")
                                .accessibilityHint("The app's own bucketing applies again, and analytics include the device")
                        }
                    }
                } footer: {
                    Text(
                        snapshot.overriddenKeys.isEmpty
                            ? "No experiment forced."
                            : "Forced, so excluded from analytics: \(snapshot.overriddenKeys.joined(separator: ", "))"
                    )
                }
            }
        }
    }

    /// One experiment: its key, a picker of its variants, and Clear once forced.
    struct ExperimentOverrideRow: View {
        let experiment: DebugDrawerExperiment
        let isOverridden: Bool
        let send: (DebugDrawerExperimentOverrides.Command) -> Void

        var body: some View {
            DebugDrawerRow(experiment.key) {
                if isOverridden {
                    Text("Forced")
                        .debugDrawerForegroundStyle(.accent)
                    Button("Clear") { send(.clearOverride(experiment: experiment.key)) }
                        .debugDrawerButtonStyle(.secondary)
                        .accessibilityLabel("Clear \(experiment.key)")
                        .accessibilityHint("The app's own bucketing applies again")
                }
            } accessory: {
                Picker(experiment.key, selection: Binding {
                    experiment.assignedVariant ?? ""
                } set: { variant in
                    // The placeholder for an experiment the app hasn't bucketed is no variant.
                    if experiment.variants.contains(variant) {
                        send(.setOverride(experiment: experiment.key, variant: variant))
                    }
                }) {
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
            .accessibilityIdentifier("Experiment-\(experiment.key)")
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The experiments the app's adapter lists; release builds show nothing.
        @MainActor public static var experimentOverrides: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerExperimentOverrides.pluginID, title: "Experiments", icon: "flask",
                snapshot: DebugDrawerExperimentOverrides.Snapshot.self, command: DebugDrawerExperimentOverrides.Command.self
            ) { _ in
                ExperimentOverridesSidecarPlugin()
            }
        }
    }

    /// Draws nothing.
    struct ExperimentOverridesSidecarPlugin: DebugDrawerPlugin {
        let title = "Experiments"
        let icon = "flask"

        var body: some View {
            EmptyView()
        }
    }
#endif
