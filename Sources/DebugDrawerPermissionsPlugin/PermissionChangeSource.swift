#if DEBUG
    /// Tells the plugin when a status may have changed: the system's notifications in production
    /// (`SystemPermissionChangeSource`), a fake the test fires in tests.
    @MainActor
    protocol PermissionChangeSource {
        /// Calls `onChange` each time a status may have changed from now on, awaiting each call.
        func observe(_ onChange: @escaping @MainActor () async -> Void)
    }
#endif
