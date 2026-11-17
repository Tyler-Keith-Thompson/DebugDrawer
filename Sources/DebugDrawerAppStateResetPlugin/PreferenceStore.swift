#if DEBUG
    import Foundation

    /// The UserDefaults domains the plugin clears: the app's own, named by its bundle identifier,
    /// and each app group's suite.
    @MainActor
    protocol PreferenceStore {
        /// The keys set in domain `name`'s persistent domain, sorted; empty when it has none.
        func keys(inDomain name: String) -> [String]
        /// Removes `keys` from domain `name` and writes the domain to disk, so a process that
        /// exits next keeps the removal.
        func remove(_ keys: [String], fromDomain name: String)
    }

    /// The real defaults: `UserDefaults.standard` for the app's domain, and a suite's own
    /// `UserDefaults` for an app group, whose domain lives in the group's container.
    struct _PreferenceStore: PreferenceStore {
        /// The app's domain: its bundle identifier.
        let appDomain: String

        func keys(inDomain name: String) -> [String] {
            (defaults(for: name)?.persistentDomain(forName: name) ?? [:]).keys.sorted()
        }

        // Key by key rather than `removePersistentDomain(forName:)`: DebugDrawer's own keys stay
        // unless they were asked for, and what is removed is exactly what the confirmation listed.
        func remove(_ keys: [String], fromDomain name: String) {
            guard let defaults = defaults(for: name) else { return }
            for key in keys {
                defaults.removeObject(forKey: key)
            }
            // Documented as unneeded for a process that keeps running; this one may exit next.
            defaults.synchronize()
        }

        private func defaults(for name: String) -> UserDefaults? {
            name == appDomain ? .standard : UserDefaults(suiteName: name)
        }
    }
#endif
