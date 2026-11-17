#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A conditioning profile in the Conditions section: a switch that turns it on and off, its
    /// name, and below it the hosts it applies to and what it does. Selected, it shows Edit, Move
    /// Up, Move Down and Delete.
    struct NetworkConditionRow: View {
        let profile: NetworkConditionProfile
        let isSelected: Bool
        let isFirst: Bool
        let isLast: Bool
        let onSelect: () -> Void
        let setEnabled: (Bool) -> Void
        let edit: () -> Void
        let move: (Int) -> Void
        let delete: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                // At accessibility text sizes the switch sits above the summary, which then has the
                // row's width.
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                    : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
                layout {
                    Toggle(isOn: Binding(get: { profile.isEnabled }, set: { setEnabled($0) })) {
                        Text(profile.name)
                    }
                    .toggleStyle(.switch)
                    .labelsHidden()
                    #if os(macOS)
                        .controlSize(.mini)
                    #endif
                    .accessibilityLabel("Use \(profile.name)")
                    Button(action: onSelect) {
                        summary
                            .debugDrawerRowPadding()
                            .contentShape(Rectangle())
                    }
                    .debugDrawerButtonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityHint(isSelected ? "Hides the condition's actions" : "Shows Edit, Move and Delete")
                }
                if isSelected {
                    DebugDrawerActionRow {
                        Button("Edit", action: edit)
                            .accessibilityLabel("Edit \(profile.name)")
                        Button("Move Up") { move(-1) }
                            .disabled(isFirst)
                            .accessibilityLabel("Move Up \(profile.name)")
                        Button("Move Down") { move(1) }
                            .disabled(isLast)
                            .accessibilityLabel("Move Down \(profile.name)")
                    } trailing: {
                        Button("Delete", role: .destructive, action: delete)
                            .debugDrawerButtonStyle(.destructive)
                            .accessibilityLabel("Delete \(profile.name)")
                    }
                }
            }
        }

        private var summary: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .debugDrawerFont(.body)
                    .debugDrawerForegroundStyle(profile.isEnabled ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(profile.effectSummary)
                    .debugDrawerFont(.value)
                    .debugDrawerForegroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(profile.hostSummary)
                    .debugDrawerFont(.code)
                    .debugDrawerForegroundStyle(.tertiary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                if profile.hasInvalidHost {
                    Text("Invalid host pattern: this condition never applies.")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.error)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
#endif
