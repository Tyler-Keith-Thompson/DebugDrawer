#if DEBUG
    /// The swap of `CLLocationManager`'s location methods for a simulator's, which the Location
    /// plugin's model makes as each drawer installs it and undoes as each removes it.
    /// `_LocationInterception` in production, which routes the app's managers to the simulator of
    /// the drawer that installed the plugin last; tests pass a fake that records the calls, so
    /// nothing swaps a method of the test process.
    @MainActor
    protocol LocationInterception {
        /// Gives the app's managers to this interception's simulator while `drawer` is the latest
        /// to hold the plugin, and swaps the methods; a second call changes only the methods put
        /// back since.
        func install(for drawer: ObjectIdentifier)

        /// Stops giving the managers to this interception's simulator for `drawer`: the drawer
        /// that installed the plugin before gets them, or, with none left, every manager goes back
        /// to Core Location and every swapped method gets its original implementation back,
        /// except one other code swapped again since.
        func uninstall(for drawer: ObjectIdentifier)
    }
#endif
