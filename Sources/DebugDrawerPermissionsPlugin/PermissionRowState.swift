#if DEBUG
    /// A permission as the drawer shows it.
    struct PermissionRowState: Identifiable, Hashable, Sendable {
        let permission: DeclaredPermission
        let status: PermissionStatus
        let request: PermissionRequest

        var id: PermissionKind {
            permission.kind
        }
    }
#endif
