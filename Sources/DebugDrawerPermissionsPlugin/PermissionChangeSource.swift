#if DEBUG
    /// Tells the plugin when a status may have changed: the system's notifications in production
    /// (`SystemPermissionChangeSource`), a fake the test fires in tests.
    @MainActor
    protocol PermissionChangeSource {
        /// Calls `onChange` each time a status may have changed from now on, awaiting each call.
        func observe(_ onChange: @escaping @MainActor () async -> Void)

        /// Stops calling the closure ``observe(_:)`` was given and lets go of what it took to
        /// observe. Observing again starts afresh.
        func stop()
    }
#endif
