#if DEBUG
    import Foundation

    // MARK: - The drawers a plugin is in

    // A plugin can't keep the drawers it was installed in: it is a value (often a struct), and
    // the copy that calls setBadge(_:) is rarely the one a drawer was handed. So the drawers are
    // found from the plugin's ID instead, by asking every live drawer whether it holds that ID.
    // The set holds them weakly, so it keeps no drawer alive, not even until the autorelease pool
    // drains (WeakSet says why it isn't a weak hash table), and asking reads the registry each
    // drawer already keeps, so nothing has to be updated as plugins come and go. Rejected:
    // a table of drawers by plugin ID kept up in install and uninstall, which would duplicate the
    // registry and have to count a plugin held both globally and locally by one drawer.
    extension DebugDrawer {
        /// Every drawer made and not yet freed, held weakly.
        private static var liveDrawers = WeakSet<DebugDrawer>()

        /// Adds `drawer` to the drawers ``drawers(holdingPlugin:)`` searches, until it is freed.
        ///
        /// - Parameter drawer: A drawer just made.
        static func track(_ drawer: DebugDrawer) {
            liveDrawers.add(drawer)
        }

        /// The drawers that hold a plugin under `id`, globally or locally, or ``shared`` when
        /// none does, so a plugin that posts before it is installed reaches the app's drawer.
        ///
        /// - Parameter id: The plugin's ``DebugDrawerPlugin/id``.
        /// - Returns: One or more drawers, in no particular order.
        static func drawers(holdingPlugin id: String) -> [DebugDrawer] {
            let holding = liveDrawers.allObjects.filter { $0.registeredPlugin(id: id) != nil }
            return holding.isEmpty ? [shared] : holding
        }
    }
#endif
