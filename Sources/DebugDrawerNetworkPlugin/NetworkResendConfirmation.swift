#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The question asked before a request the server may act on (a POST, PUT, PATCH or DELETE)
    /// is sent again, in place under the button that asked it, with Send and Cancel.
    struct NetworkResendConfirmation: View {
        let method: String
        let confirm: () -> Void
        let cancel: () -> Void

        var body: some View {
            DebugDrawerIssueRow("Send this \(method) again?", severity: .warning) {
                Text("The server acts on a \(method), so it may create, change or delete data a second time.")
                DebugDrawerActionRow {
                    Button("Send", action: confirm)
                        .debugDrawerButtonStyle(.primary)
                        .accessibilityLabel("Send the \(method) again")
                    Button("Cancel", action: cancel)
                        .accessibilityLabel("Cancel resending")
                }
            }
        }
    }
#endif
