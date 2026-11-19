#if DEBUG
    /// The swizzles of `CLLocationManager+LocationSimulator.swift`, which ask
    /// ``LocationSimulator/shared``.
    struct _LocationInterception: LocationInterception {
        func install() {
            LocationSwizzles.install()
        }

        func uninstall() {
            LocationSwizzles.uninstall()
        }
    }
#endif
