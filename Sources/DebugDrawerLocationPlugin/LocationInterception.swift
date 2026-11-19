#if DEBUG
    /// The swap of `CLLocationManager`'s location methods for the simulator's, which the Location
    /// plugin makes as a drawer installs it and puts back as the last drawer removes it.
    /// `_LocationInterception` in production; tests pass a fake that counts the calls, so nothing
    /// swaps a method of the test process.
    @MainActor
    protocol LocationInterception {
        /// Swaps the methods; a second call changes only the ones put back since.
        func install()

        /// Gives every swapped method its original implementation back, except one other code
        /// swapped again since.
        func uninstall()
    }
#endif
