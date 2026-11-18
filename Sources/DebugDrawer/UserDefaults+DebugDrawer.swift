#if DEBUG
    import Foundation

    package extension UserDefaults {
        // nonisolated(unsafe): UserDefaults is documented as thread-safe, but the class isn't marked
        // Sendable; Location's simulator reads it from whatever thread the app calls it on.
        /// Where DebugDrawer and its plugins keep their own state: a suite named
        /// ``debugDrawerSuiteName``, apart from the app's standard defaults, so none of it shows
        /// among the app's keys (in the UserDefaults plugin, say). The first time it is opened, the
        /// drawer's keys still in `.standard` move into it (``debugDrawerSuite(named:movingKeysFrom:)``).
        nonisolated(unsafe) static let debugDrawer = debugDrawerSuite(named: debugDrawerSuiteName, movingKeysFrom: .standard)

        /// The name of ``debugDrawer``'s suite: the app's bundle identifier followed by
        /// `.debugdrawer`, so on the Mac, where apps outside the sandbox share a preferences folder,
        /// each app keeps its drawer's state apart.
        static var debugDrawerSuiteName: String {
            (Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName) + ".debugdrawer"
        }

        /// The suite named `name`, after moving the drawer's keys from `source` into it the first
        /// time: each key under one of ``debugDrawerMovedKeyPrefixes`` is copied unless the suite
        /// already holds it, then removed from `source`. A flag in the suite records the move, so a
        /// key written to `source` later stays there.
        ///
        /// - Parameters:
        ///   - name: The suite's name; never the app's bundle identifier.
        ///   - source: Where the keys were kept before: the app's standard defaults.
        /// - Returns: The suite.
        static func debugDrawerSuite(named name: String, movingKeysFrom source: UserDefaults) -> UserDefaults {
            // `UserDefaults(suiteName:)` returns nil only for the app's own domain and the global
            // domain; every name passed here ends in `.debugdrawer` or is a test's unique name, and
            // a drawer with nowhere to save is a programming error worth stopping at.
            let suite = UserDefaults(suiteName: name)!
            guard !suite.bool(forKey: movedFromStandardKey) else { return suite }
            let moved = source.dictionaryRepresentation().filter { key, _ in
                debugDrawerMovedKeyPrefixes.contains { key.hasPrefix($0) }
            }
            for (key, value) in moved {
                if suite.object(forKey: key) == nil {
                    suite.set(value, forKey: key)
                }
                source.removeObject(forKey: key)
            }
            suite.set(true, forKey: movedFromStandardKey)
            return suite
        }

        // Listed rather than every `com.debugdrawer.` key: Tweaks' values and Feature Flags'
        // overrides stay in the app's defaults (`TweakStorage`, `FeatureFlagOverrideStorage`),
        // where the app reads them.
        /// The prefixes of the keys the drawer and its plugins keep in ``debugDrawer``: the
        /// drawer's collapsed sections, layout, HUD and silenced notices, Deep Link's history,
        /// Location's simulated location and Screen Recording's Show Touches.
        static let debugDrawerMovedKeyPrefixes = [
            "com.debugdrawer.collapsed.",
            "com.debugdrawer.layout",
            "com.debugdrawer.hud",
            "com.debugdrawer.noticesMuted",
            "com.debugdrawer.deeplink.",
            "com.debugdrawer.location.",
            "com.debugdrawer.screenRecording."
        ]
    }

    extension UserDefaults {
        /// The flag in ``debugDrawer``'s suite that records its keys were moved from `.standard`.
        fileprivate static let movedFromStandardKey = "com.debugdrawer.movedFromStandard"
    }
#endif
