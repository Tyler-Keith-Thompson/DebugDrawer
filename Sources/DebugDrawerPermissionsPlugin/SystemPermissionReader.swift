#if DEBUG
    /// Reads and requests the permissions one framework owns, for `SystemPermissionAuthority`.
    @MainActor
    protocol SystemPermissionReader {
        /// The permission's status now. Never prompts the user.
        func status(of permission: DeclaredPermission) async -> PermissionStatus

        /// Shows the system's prompt for the permission, returning once it is answered.
        func request(_ permission: DeclaredPermission) async

        /// Lets go of the framework's manager, if the reader made one, and has a request still
        /// waiting for an answer return.
        func stop()
    }

    extension SystemPermissionReader {
        /// Holds nothing to let go of.
        func stop() {}
    }
#endif
