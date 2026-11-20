#if DEBUG
    import DebugDrawer
    import DebugDrawerNetwork
    import SwiftUI

    /// A mock rule in the Mocks section: a switch that turns it on and off, its name and status,
    /// and below them its methods and the host and path it matches. Selected, it shows Edit, Move
    /// Up, Move Down and Delete.
    struct NetworkMockRuleRow: View {
        let rule: NetworkMockRule
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
                    Toggle(isOn: Binding(get: { rule.isEnabled }, set: { setEnabled($0) })) {
                        Text(rule.name)
                    }
                    .toggleStyle(.switch)
                    .labelsHidden()
                    #if os(macOS)
                        .controlSize(.mini)
                    #endif
                    .accessibilityLabel("Use \(rule.name)")
                    Button(action: onSelect) {
                        summary
                            .debugDrawerRowPadding()
                            .contentShape(Rectangle())
                    }
                    .debugDrawerButtonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                    .accessibilityHint(isSelected ? "Hides the mock's actions" : "Shows Edit, Move and Delete")
                }
                if isSelected {
                    DebugDrawerActionRow {
                        Button("Edit", action: edit)
                            .accessibilityLabel("Edit \(rule.name)")
                        Button("Move Up") { move(-1) }
                            .disabled(isFirst)
                            .accessibilityLabel("Move Up \(rule.name)")
                        Button("Move Down") { move(1) }
                            .disabled(isLast)
                            .accessibilityLabel("Move Down \(rule.name)")
                    } trailing: {
                        Button("Delete", role: .destructive, action: delete)
                            .debugDrawerButtonStyle(.destructive)
                            .accessibilityLabel("Delete \(rule.name)")
                    }
                }
            }
        }

        private var summary: some View {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline) {
                    Text(rule.name)
                        .debugDrawerFont(.body)
                        .debugDrawerForegroundStyle(rule.isEnabled ? .primary : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !dynamicTypeSize.isAccessibilitySize {
                        status
                    }
                }
                // At accessibility text sizes the status has no room beside the name.
                if dynamicTypeSize.isAccessibilitySize {
                    status
                }
                // At accessibility text sizes the pattern has a line of its own, and wraps whole.
                let patternLayout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                patternLayout {
                    Text(rule.methodSummary)
                        .debugDrawerForegroundStyle(.secondary)
                    Text(rule.patternSummary)
                        .debugDrawerForegroundStyle(.tertiary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 3)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .debugDrawerFont(.code)
                if rule.hasInvalidPattern {
                    Text("Invalid pattern: this mock never answers.")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.error)
                }
            }
            .accessibilityElement(children: .combine)
        }

        private var status: some View {
            Text(String(rule.response.status))
                .debugDrawerFont(.value)
                .debugDrawerForegroundStyle(rule.response.status >= 400 ? .error : .primary)
                .accessibilityLabel("Status \(rule.response.status)")
        }
    }
#endif
