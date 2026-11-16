#if DEBUG
    /// Reads and requests permissions: the system's frameworks in production
    /// (`SystemPermissionAuthority`), a fake in tests.
    @MainActor
    protocol PermissionAuthority {
        /// The permission's status now. Never prompts the user.
        func status(of permission: DeclaredPermission) async -> PermissionStatus

        /// Asks the user for the permission with the system's prompt, returning once they have
        /// answered. Called only while the status is `notDetermined` and the Info.plist declares
        /// what the request needs.
        func request(_ permission: DeclaredPermission) async
    }
#endif
