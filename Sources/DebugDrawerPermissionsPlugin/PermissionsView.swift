#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Every declared permission with its status, a Request button while the user hasn't
    /// decided, and an Open Settings button.
    struct PermissionsView: View {
        let rows: [PermissionRowState]
        let onRequest: (PermissionKind) -> Void
        let onOpenSettings: (PermissionKind) -> Void

        var body: some View {
            DebugDrawerSection {
                ForEach(rows) { row in
                    PermissionRow(
                        row: row,
                        onRequest: { onRequest(row.permission.kind) },
                        onOpenSettings: { onOpenSettings(row.permission.kind) }
                    )
                }
            } footer: {
                Text("The permissions the Info.plist declares, read again each time the app becomes active.")
            }
        }
    }
#endif
