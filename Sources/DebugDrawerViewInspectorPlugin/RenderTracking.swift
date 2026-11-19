#if DEBUG
    import Foundation

    // `.trackRenders(_:)` runs in the app's own views, where no drawer or plugin is at hand, so the
    // tracker it records into is found here, as the plugin is installed and uninstalled. The drawer
    // that installed the plugin last gets the counts: a drawer of a test's own, installed while the
    // app's drawer holds the plugin too, sees its own views' counts and the app's drawer none until
    // it is removed. Rejected: the first install keeping the counts (a drawer installed later would
    // never see any), and recording into every installed plugin's tracker (each count kept twice,
    // and the drawer's own views counted by another drawer's plugin).

    /// The trackers `.trackRenders(_:)` records into: one per drawer that holds the View Inspector
    /// plugin, the latest install's taking every count.
    @MainActor
    enum RenderTracking {
        /// The drawers holding the plugin, in the order they installed it, each with its plugin's
        /// tracker.
        private static var installations: [(drawer: ObjectIdentifier, tracker: RenderTracker)] = []

        /// The tracker the counts go to: the latest install's, or none while no drawer holds the
        /// plugin, when `.trackRenders(_:)` counts nothing.
        static var tracker: RenderTracker? {
            installations.last?.tracker
        }

        /// Sends the counts to `tracker` from now on, while `drawer` holds the plugin; a drawer that
        /// holds it already changes nothing.
        static func install(_ tracker: RenderTracker, for drawer: ObjectIdentifier) {
            guard !installations.contains(where: { $0.drawer == drawer }) else { return }
            installations.append((drawer, tracker))
        }

        /// Stops sending counts to the tracker `drawer` installed; the install before it gets them
        /// again.
        static func uninstall(for drawer: ObjectIdentifier) {
            installations.removeAll { $0.drawer == drawer }
        }
    }
#endif
