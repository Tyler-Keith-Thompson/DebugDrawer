#if DEBUG
    import DebugDrawer
    import DebugDrawerNetwork
    import SwiftUI

    /// The Mocks section: the rules in the order they are tried, each with its switch, then a
    /// note on how they apply, and Add Mock. A problem reading or saving them shows above the list.
    struct NetworkMocksSection: View {
        let rules: [NetworkMockRule]
        let issue: NetworkMocksIssue?
        /// The rule whose actions show, if any.
        @Binding var selected: NetworkMockRule.ID?
        let setEnabled: (NetworkMockRule.ID, Bool) -> Void
        let add: () -> Void
        let edit: (NetworkMockRule) -> Void
        let move: (NetworkMockRule.ID, Int) -> Void
        let delete: (NetworkMockRule.ID) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection("Mocks") {
                    if let issue {
                        DebugDrawerIssueRow(issue == .notSaved ? "Not saved" : "Not loaded", severity: issue == .notSaved ? .warning : .error) {
                            Text(issue.message)
                        }
                    }
                    ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                        NetworkMockRuleRow(
                            rule: rule,
                            isSelected: selected == rule.id,
                            isFirst: index == 0,
                            isLast: index == rules.count - 1,
                            onSelect: { selected = selected == rule.id ? nil : rule.id },
                            setEnabled: { setEnabled(rule.id, $0) },
                            edit: { edit(rule) },
                            move: { move(rule.id, $0) },
                            delete: {
                                selected = nil
                                delete(rule.id)
                            }
                        )
                    }
                } footer: {
                    Text(rules.isEmpty
                        ? "No mocks. Add one, or open a request and choose Mock This to answer it without the server."
                        : "The first mock that is on and matches answers a request. Requests no mock matches reach the network.")
                }
                DebugDrawerActionRow {
                    Button("Add Mock", action: add)
                        .accessibilityLabel("Add Mock")
                }
            }
        }
    }
#endif
