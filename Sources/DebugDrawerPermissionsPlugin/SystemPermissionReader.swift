#if DEBUG
    /// Reads and requests the permissions one framework owns, for `SystemPermissionAuthority`.
    @MainActor
    protocol SystemPermissionReader {
        /// The permission's status now. Never prompts the user.
        func status(of permission: DeclaredPermission) async -> PermissionStatus

        /// Shows the system's prompt for the permission, returning once it is answered.
        func request(_ permission: DeclaredPermission) async
    }
#endif
