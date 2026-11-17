#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// What the list's controls do, each passed the item it acts on.
    struct KeychainListActions {
        var select: (KeychainItem) -> Void = { _ in }
        var edit: (KeychainItem) -> Void = { _ in }
        var delete: (KeychainItem) -> Void = { _ in }
        var add: () -> Void = {}
        var reload: () -> Void = {}
    }

    /// The keychain's items: the access group filter, the text filter, a row per item with the
    /// open one's detail, and Add Password and Reload.
    struct KeychainListView: View {
        let items: [KeychainItem]
        let accessGroups: [String]
        @Binding var filter: KeychainFilter
        let selection: KeychainSelection?
        /// The keychain's refusal to be read, if it refused.
        let failure: KeychainError?
        /// The last change the keychain refused.
        let issue: KeychainIssue?
        let redaction: DebugDrawerRedaction
        let actions: KeychainListActions

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection {
                    if !accessGroups.isEmpty {
                        DebugDrawerRow("Access group") { groupPicker }
                    }
                    if let failure {
                        DebugDrawerIssueRow("Keychain unavailable", severity: .error) {
                            Text(failure.message)
                        }
                    }
                    DebugDrawerSearchableList("Filter...", text: $filter.text, accessibilityLabel: "Filter keychain items") {
                        ForEach(items) { item in
                            KeychainRow(
                                item: item,
                                detail: selection?.item.id == item.id ? selection : nil,
                                redaction: redaction,
                                onSelect: { actions.select(item) },
                                onEdit: item.itemClass == .genericPassword ? { actions.edit(item) } : nil,
                                onDelete: { actions.delete(item) }
                            )
                        }
                    }
                    if let issue {
                        DebugDrawerIssueRow("Keychain refused", severity: .error) {
                            Text(issue.message)
                        }
                    }
                }

                DebugDrawerActionRow {
                    Button("Add Password…", action: actions.add)
                        .accessibilityLabel("Add Password…")
                        .accessibilityHint("Opens a form to add a generic password")
                    Button("Reload", action: actions.reload)
                        .accessibilityLabel("Reload keychain items")
                }
            }
        }

        private var groupPicker: some View {
            KeychainChoiceMenu(title: "Access group", selection: $filter.accessGroup, choices: [nil] + accessGroups.map(Optional.some)) {
                $0 ?? "All"
            }
        }
    }
#endif
