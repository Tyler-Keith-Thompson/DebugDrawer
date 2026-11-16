#if DEBUG
    import SwiftUI

    /// One flag: the control that overrides it, its key and live value, and a button that clears
    /// its override while it has one.
    struct FeatureFlagRow: View {
        let row: FeatureFlagRowState
        let onOverride: (FeatureFlagValue) -> Void
        let onClear: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    control
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if row.isOverridden {
                        Button(action: onClear) {
                            Label("Clear override", systemImage: "arrow.uturn.backward")
                                .labelStyle(.iconOnly)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .accessibilityLabel("Clear override of \(row.title)")
                        .help("Use the live value")
                    }
                }
                facts
                if let detail = row.detail {
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }

        @ViewBuilder
        private var control: some View {
            switch row.control {
            case let .toggle(isOn):
                Toggle(isOn: Binding(get: { isOn }, set: { onOverride(.bool($0)) })) {
                    title
                }
                .toggleStyle(.switch)
                .controlSize(.small)

            case let .number(number):
                labeled {
                    // A field commits its value when it loses focus too, unchanged or unparsable text
                    // as the value it showed, which is no override.
                    TextField(row.title, value: Binding(get: { number }, set: { if $0 != number { onOverride(.number($0)) } }), format: .number)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .accessibilityLabel(row.title)
                }

            case let .text(text):
                labeled {
                    TextField(row.title, text: Binding(get: { text }, set: { onOverride(.string($0)) }))
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .autocorrectionDisabled()
                        .accessibilityLabel(row.title)
                }
            }
        }

        /// The key, the live value and, while overridden, a tag saying so: side by side, or one above
        /// the other at accessibility text sizes.
        private var facts: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
            return layout {
                if row.title != row.id {
                    Text(row.id)
                        .font(.system(.caption2, design: .monospaced))
                }
                Text("Live: \(row.liveValue.description)")
                    .font(.caption2)
                if let override = row.override {
                    Text("Overridden")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Overridden with \(override.description)")
                }
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .combine)
        }

        private var title: some View {
            Text(row.title)
                .font(.caption)
        }

        /// The title beside the field, or above it at accessibility text sizes, where side by side
        /// leaves the field too little width.
        private func labeled(@ViewBuilder _ control: () -> some View) -> some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
            return layout {
                // The field carries the title as its label, so VoiceOver reads it once.
                title.accessibilityHidden(true)
                control()
            }
        }
    }
#endif
