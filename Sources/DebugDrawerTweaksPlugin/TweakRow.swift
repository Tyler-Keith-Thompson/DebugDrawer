#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One tweak's control, or an action's button, with a reset button while the tweak reads other
    /// than its default.
    struct TweakRow: View {
        let row: TweakRowState
        let onChange: (TweakStoredValue) -> Void
        let onReset: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            HStack(spacing: 6) {
                control
                    .frame(maxWidth: .infinity, alignment: .leading)
                if row.isModified {
                    Button(action: onReset) {
                        Label("Reset", systemImage: "arrow.uturn.backward")
                            .labelStyle(.iconOnly)
                    }
                    .debugDrawerButtonStyle(.borderless)
                    .accessibilityLabel("Reset \(row.title)")
                    .help("Reset to the default")
                }
            }
            .debugDrawerRowPadding()
        }

        @ViewBuilder
        private var control: some View {
            switch row.control {
            case let .toggle(isOn):
                Toggle(isOn: Binding(get: { isOn }, set: { onChange(.bool($0)) })) {
                    title
                }
                .toggleStyle(.switch)
                .controlSize(.small)

            case let .picker(options, selection):
                labeled {
                    Picker(row.title, selection: Binding(get: { selection }, set: { onChange($0) })) {
                        ForEach(options, id: \.value) { option in
                            Text(option.title).tag(option.value)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .controlSize(.small)
                    .accessibilityLabel(row.title)
                }

            case let .text(text):
                labeled {
                    TextField(row.title, text: Binding(get: { text }, set: { onChange(.string($0)) }))
                        .debugDrawerTextFieldStyle()
                        .autocorrectionDisabled()
                        .accessibilityLabel(row.title)
                }

            case let .stepper(value, range, step):
                Stepper(value: Binding(get: { value }, set: { onChange(.int($0)) }), in: range, step: step) {
                    HStack(alignment: .firstTextBaseline) {
                        title
                        Text(value, format: .number)
                            .debugDrawerFont(.value)
                    }
                }
                .controlSize(.small)
                .accessibilityValue(Text(value, format: .number))

            case let .action(perform):
                Button(row.title) { perform() }
                    .debugDrawerButtonStyle(.secondary)
            }
        }

        private var title: some View {
            Text(row.title)
                .debugDrawerFont(.body)
                // Wraps rather than truncates beside a switch at large text sizes.
                .fixedSize(horizontal: false, vertical: true)
        }

        /// The title beside the control, or above it at accessibility text sizes, where side by
        /// side leaves the control too little width.
        private func labeled(@ViewBuilder _ control: () -> some View) -> some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            return layout {
                // The control carries the title as its label, so VoiceOver reads it once.
                title.accessibilityHidden(true)
                control()
            }
        }
    }
#endif
