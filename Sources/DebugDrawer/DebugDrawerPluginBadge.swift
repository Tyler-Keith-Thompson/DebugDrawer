#if DEBUG
    import Foundation

    // MARK: - A store's badge in the drawers that installed it

    // A shipped plugin's count lives in a store (its reports, hangs, payloads), and the drawers
    // that show it are the ones whose install(in:) was handed a plugin over that store. Keeping
    // them here, rather than finding them by plugin ID as DebugDrawerPlugin.setBadge(_:) does,
    // means a count change reaches only the drawers that show that count: not another drawer that
    // holds a plugin of the same ID over another store, and not the shared drawer once the last
    // drawer removed the plugin. Rejected: setBadge(_:) by ID from the store's callback, which
    // badges the shared drawer before any install and after the last uninstall (its fallback),
    // and every drawer holding the ID whatever store it shows.
    /// One plugin's badge from one store: shown in each drawer that installed the plugin over the
    /// store, cleared from each as it removes the plugin, and nowhere before the first install.
    ///
    /// The store calls ``update(_:)`` with its count at every change, and the plugin's
    /// ``DebugDrawerPlugin/install(in:)`` and ``DebugDrawerPlugin/uninstall(from:)`` call
    /// ``show(_:in:)`` and ``remove(from:)``. Drawers are held weakly.
    @MainActor
    package final class DebugDrawerPluginBadge {
        /// The plugin's ``DebugDrawerPlugin/id``, which the badge is set under.
        package let pluginID: String
        /// The drawers that installed the plugin over the store, held weakly.
        private let drawers = NSHashTable<DebugDrawer>.weakObjects()

        /// A badge shown in no drawer yet.
        ///
        /// - Parameter pluginID: The plugin's ``DebugDrawerPlugin/id``.
        package init(pluginID: String) {
            self.pluginID = pluginID
        }

        /// Shows `count` in `drawer`, and every count ``update(_:)`` is given from now on.
        ///
        /// - Parameters:
        ///   - count: The store's count now.
        ///   - drawer: A drawer that just installed the plugin.
        package func show(_ count: Int, in drawer: DebugDrawer) {
            drawers.add(drawer)
            drawer.setBadge(count, forPlugin: pluginID)
        }

        /// Clears the badge from `drawer` and stops showing counts there.
        ///
        /// - Parameter drawer: A drawer that just removed the plugin.
        package func remove(from drawer: DebugDrawer) {
            drawers.remove(drawer)
            drawer.setBadge(0, forPlugin: pluginID)
        }

        /// Shows `count` in every drawer the badge is shown in; zero or less clears it.
        ///
        /// - Parameter count: The store's new count.
        package func update(_ count: Int) {
            for drawer in drawers.allObjects {
                drawer.setBadge(count, forPlugin: pluginID)
            }
        }
    }
#endif
