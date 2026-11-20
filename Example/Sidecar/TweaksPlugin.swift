import DebugDrawer
import DebugDrawerSidecarKit
import DebugDrawerTweaks
import SwiftUI

extension DebugDrawerSidecarPlugin {
    /// The host's production-safe tweaks (`DebugDrawerReceiverCapability.tweaks`).
    @MainActor static var tweaks: DebugDrawerSidecarPlugin {
        DebugDrawerSidecarPlugin(
            id: TweaksModel.pluginID, title: "Tweaks", icon: "slider.horizontal.3",
            snapshot: TweaksModel.Snapshot.self, command: TweaksModel.Command.self
        ) { transport in
            SidecarTweaksPlugin(transport: transport)
        }
    }
}

/// Each production-safe tweak with the control it declares, and Reset All.
struct SidecarTweaksPlugin: DebugDrawerPlugin {
    let transport: DebugDrawerPluginTransport<TweaksModel.Snapshot, TweaksModel.Command>
    let title = "Tweaks"
    let icon = "slider.horizontal.3"

    var body: some View {
        SidecarTweaksView(transport: transport)
    }
}

private struct SidecarTweaksView: View {
    @ObservedObject var transport: DebugDrawerPluginTransport<TweaksModel.Snapshot, TweaksModel.Command>

    var body: some View {
        DebugDrawerSection("Production-safe tweaks") {
            ForEach(transport.snapshot.tweaks, id: \.key) { entry in
                SidecarTweakRow(entry: entry) { transport.send(.setValue(key: entry.key, value: $0)) }
            }
        }
        DebugDrawerActionRow {
            Button("Reset All") { transport.send(.resetAll) }
        }
    }
}

/// One tweak, drawn with its control; `set` sends a new value.
private struct SidecarTweakRow: View {
    let entry: TweaksModel.Entry
    let set: @MainActor @Sendable (TweakStoredValue) -> Void
    @State private var text = ""

    var body: some View {
        switch entry.control {
        case .toggle:
            DebugDrawerRow(entry.title, isOn: Binding(get: { entry.value.isOn }, set: { set(.bool($0)) }))
        case let .picker(options):
            DebugDrawerRow(entry.title) {
                Picker(entry.title, selection: Binding(get: { entry.value }, set: set)) {
                    ForEach(options, id: \.value) { option in
                        Text(option.title).tag(option.value)
                    }
                }
                .labelsHidden()
                .accessibilityLabel(entry.title)
            }
        case .text:
            DebugDrawerRow(entry.title) {
                TextField(entry.title, text: $text)
                    .debugDrawerTextFieldStyle()
                    .accessibilityLabel(entry.title)
                    .onSubmit { set(.string(text)) }
                    .onChange(of: entry.value, initial: true) { _, value in text = value.description }
            }
        case let .stepper(range, step):
            DebugDrawerRow(entry.title) {
                Stepper(
                    entry.value.description,
                    value: Binding(get: { entry.value.number ?? range.lowerBound }, set: { set(.int($0)) }),
                    in: range,
                    step: step
                )
                .accessibilityLabel(entry.title)
            }
        }
    }
}

extension TweakStoredValue {
    /// A toggle's value.
    fileprivate var isOn: Bool {
        if case let .bool(value) = self { value } else { false }
    }

    /// A stepper's value.
    fileprivate var number: Int? {
        if case let .int(value) = self { value } else { nil }
    }
}
