#if DEBUG
    /// The swizzles of `CLLocationManager+LocationSimulator.swift`, routed to `simulator` while
    /// the drawer it is installed for is the latest to hold the plugin.
    struct _LocationInterception: LocationInterception {
        /// The simulator the app's managers ask while this interception's drawer is the latest.
        let simulator: LocationSimulator

        func install(for drawer: ObjectIdentifier) {
            LocationSwizzles.install(simulator, for: drawer)
        }

        func uninstall(for drawer: ObjectIdentifier) {
            LocationSwizzles.uninstall(for: drawer)
        }
    }
#endif
