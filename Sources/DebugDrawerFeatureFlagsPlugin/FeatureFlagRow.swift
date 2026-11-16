#if DEBUG
    import DebugDrawer
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
                        .debugDrawerButtonStyle(.borderless)
                        .accessibilityLabel("Clear override of \(row.title)")
                        .help("Use the live value")
                    }
                }
                facts
                if let detail = row.detail {
                    Text(detail)
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                }
            }
            .debugDrawerRowPadding()
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
                        .debugDrawerTextFieldStyle()
                        .accessibilityLabel(row.title)
                }

            case let .text(text):
                labeled {
                    TextField(row.title, text: Binding(get: { text }, set: { onOverride(.string($0)) }))
                        .debugDrawerTextFieldStyle()
                        .autocorrectionDisabled()
                        .accessibilityLabel(row.title)
                }
            }
        }

        /// The key, the live value and, while overridden, a word saying so: side by side, or one above
        /// the other at accessibility text sizes.
        private var facts: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
            return layout {
                if row.title != row.id {
                    Text(row.id)
                        .debugDrawerFont(.code)
                        .debugDrawerForegroundStyle(.tertiary)
                }
                Text("Live: \(row.liveValue.description)")
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.secondary)
                if let override = row.override {
                    Text("Overridden")
                        .debugDrawerFont(.secondary)
                        .fontWeight(.semibold)
                        .debugDrawerForegroundStyle(.accent)
                        .accessibilityLabel("Overridden with \(override.description)")
                }
            }
            .accessibilityElement(children: .combine)
        }

        private var title: some View {
            Text(row.title)
                .debugDrawerFont(.body)
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
