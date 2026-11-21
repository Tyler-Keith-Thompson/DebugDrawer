import DebugDrawer
import DebugDrawerTweaks
import Foundation
import SwiftUI

// The sidecar's half of production tweaks (DD-110): the tweaks the app marked production-safe
// (`TweaksModel`, in DebugDrawerTweaks), each drawn with the control it declares (a switch, a
// picker of its options, a field and Set, a stepper over its range), Reset for one changed from its
// default, and Reset All while any is. It ships in the kit, as each tweak declares its control, so
// every sidecar would draw the same controls. A field sends only once Set is pressed, and a stepper
// keeps to the tweak's range, as the receiver refuses a value the tweak doesn't take.

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// The app's production-safe tweaks (`DebugDrawerReceiverCapability.tweaks(_:storage:scope:)`),
        /// each with the control it declares, Reset, and Reset All.
        @MainActor public static var tweaks: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: TweaksModel.pluginID, title: "Tweaks", icon: "slider.horizontal.3",
                snapshot: TweaksModel.Snapshot.self, command: TweaksModel.Command.self
            ) { transport in
                TweaksSidecarPlugin(transport: transport)
            }
        }
    }

    /// The app's production-safe tweaks, changed from the sidecar.
    struct TweaksSidecarPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<TweaksModel.Snapshot, TweaksModel.Command>
        let title = "Tweaks"
        let icon = "slider.horizontal.3"

        var body: some View {
            TweaksTransportView(transport: transport)
        }
    }

    /// The tweaks over the capability's snapshot, sending what the view asks.
    struct TweaksTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<TweaksModel.Snapshot, TweaksModel.Command>

        var body: some View {
            TweaksSidecarView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// Each tweak with its control, and Reset All while any differs from its default. A function of
    /// the snapshot and the send action.
    struct TweaksSidecarView: View {
        let snapshot: TweaksModel.Snapshot
        let send: (TweaksModel.Command) -> Void

        var body: some View {
            if snapshot.tweaks.isEmpty {
                DebugDrawerEmptyState("No Tweaks", systemImage: "slider.horizontal.3") {
                    Text("The app marks no tweak production-safe.")
                }
            } else {
                DebugDrawerSection("Production-Safe Tweaks") {
                    ForEach(snapshot.tweaks, id: \.key) { entry in
                        TweakEntryRow(entry: entry, send: send)
                    }
                    if snapshot.tweaks.contains(where: { $0.value != $0.defaultValue }) {
                        DebugDrawerActionRow {
                            Button("Reset All") { send(.resetAll) }
                                .debugDrawerButtonStyle(.secondary)
                                .accessibilityLabel("Reset All")
                                .accessibilityHint("Every tweak takes its default again")
                        }
                    }
                }
            }
        }
    }

    /// One tweak: its title, its value, the control it declares, and Reset once changed.
    struct TweakEntryRow: View {
        let entry: TweaksModel.Entry
        let send: (TweaksModel.Command) -> Void
        @State private var draft: String

        init(entry: TweaksModel.Entry, send: @escaping (TweaksModel.Command) -> Void) {
            self.entry = entry
            self.send = send
            _draft = State(initialValue: entry.value.description)
        }

        var body: some View {
            DebugDrawerRow(entry.title, systemImage: nil, details: { details }, accessory: { control })
                .onChange(of: entry.value) { _, value in
                    draft = value.description
                }
                .accessibilityIdentifier("Tweak-\(entry.key)")
        }

        @ViewBuilder
        private var control: some View {
            switch entry.control {
            case .toggle:
                Toggle(isOn: Binding { entry.value == .bool(true) } set: { send(.setValue(key: entry.key, value: .bool($0))) }) {
                    Text(entry.title)
                }
                .labelsHidden()
                .accessibilityLabel(entry.title)
            case let .picker(options):
                Picker(entry.title, selection: Binding { entry.value } set: { send(.setValue(key: entry.key, value: $0)) }) {
                    ForEach(options, id: \.value) { option in
                        Text(option.title).tag(option.value)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(entry.title)
            case .text:
                HStack(spacing: 6) {
                    TextField(entry.title, text: $draft)
                        .debugDrawerTextFieldStyle()
                        .accessibilityLabel(entry.title)
                    Button("Set") { send(.setValue(key: entry.key, value: .string(draft))) }
                        .debugDrawerButtonStyle(.primary)
                        .disabled(entry.value == .string(draft))
                        .accessibilityLabel("Set \(entry.title)")
                }
            case let .stepper(range, step):
                Stepper(
                    entry.value.description,
                    value: Binding { entry.value.int ?? range.lowerBound } set: { send(.setValue(key: entry.key, value: .int($0))) },
                    in: range,
                    step: step
                )
                .accessibilityLabel(entry.title)
                .accessibilityValue(entry.value.description)
            }
        }

        @ViewBuilder
        private var details: some View {
            Text(entry.key)
            if entry.value != entry.defaultValue {
                Text("Default \(entry.defaultValue.description)")
                Button("Reset") { send(.reset(key: entry.key)) }
                    .debugDrawerButtonStyle(.secondary)
                    .accessibilityLabel("Reset \(entry.title)")
                    .accessibilityHint("The tweak takes its default again")
            }
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The app's production-safe tweaks; release builds show nothing.
        @MainActor public static var tweaks: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: TweaksModel.pluginID, title: "Tweaks", icon: "slider.horizontal.3",
                snapshot: TweaksModel.Snapshot.self, command: TweaksModel.Command.self
            ) { _ in
                TweaksSidecarPlugin()
            }
        }
    }

    /// Draws nothing.
    struct TweaksSidecarPlugin: DebugDrawerPlugin {
        let title = "Tweaks"
        let icon = "slider.horizontal.3"

        var body: some View {
            EmptyView()
        }
    }
#endif
