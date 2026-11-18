#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The cookie count and the buttons that reload, copy and delete the cookies the filter shows.
    /// Delete All asks first, in place under the buttons.
    struct CookiesToolbar: View {
        let count: CookieCount
        let refresh: () -> Void
        let deleteAll: () -> Void
        let copy: () -> Void
        @State var isConfirming = false
        let inspection = Inspection<Self>() // from/for ViewInspector.

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text(count.label)
                    .debugDrawerFont(.value)
                    .debugDrawerForegroundStyle(.secondary)
                // The action row wraps its buttons, and stacks them at accessibility sizes.
                DebugDrawerActionRow {
                    Button("Refresh", action: refresh)
                    Button("Copy", action: copy)
                        .accessibilityHint("Copies the cookies shown as text")
                } trailing: {
                    Button("Delete All", role: .destructive) { isConfirming = true }
                        .debugDrawerButtonStyle(.destructive)
                        .disabled(count.shown == 0 || isConfirming)
                        .accessibilityHint(count.isFiltered ? "Asks, then deletes the cookies the filter shows" : "Asks, then deletes every cookie")
                }
                if isConfirming {
                    CookiesDeleteConfirmation(count: count) {
                        isConfirming = false
                        deleteAll()
                    } cancel: {
                        isConfirming = false
                    }
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }
    }

    /// The question Delete All asks, in place under the toolbar's buttons, with Delete and Cancel.
    struct CookiesDeleteConfirmation: View {
        let count: CookieCount
        let confirm: () -> Void
        let cancel: () -> Void

        var body: some View {
            DebugDrawerIssueRow(count.deleteQuestion, severity: .warning) {
                Text(count.deleteExplanation)
                DebugDrawerActionRow {
                    Button("Delete", role: .destructive, action: confirm)
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel(count.isFiltered ? "Delete the cookies shown" : "Delete all cookies")
                    Button("Cancel", action: cancel)
                        .accessibilityLabel("Cancel deleting")
                }
            }
        }
    }
#endif
