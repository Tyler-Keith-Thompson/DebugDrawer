// Badges and toasts are methods on the plugin, which exists in every build, so a plugin's code
// calls them unchanged in release, where the drawer doesn't exist and they do nothing.
public extension DebugDrawerPlugin {
    /// Shows `count` on the plugin's section header in every drawer that holds the plugin; zero
    /// or less clears it.
    ///
    /// Each drawer the plugin is registered with, globally or locally, gets the badge, as
    /// ``DebugDrawer/setBadge(_:forPlugin:)`` gives it; a plugin no drawer holds yet
    /// badges ``DebugDrawer/shared``.
    ///
    /// - Parameter count: The number to show.
    @MainActor func setBadge(_ count: Int) {
        #if DEBUG
            for drawer in DebugDrawer.drawers(holdingPlugin: id) {
                drawer.setBadge(count, forPlugin: id)
            }
        #endif
    }

    /// Removes the plugin's badge from every drawer that holds the plugin, or from
    /// ``DebugDrawer/shared`` when none does.
    @MainActor func clearBadge() {
        setBadge(0)
    }

    /// Raises a toast while the drawer is closed; tapping it opens the drawer at this plugin.
    /// Posts from one plugin coalesce into one toast that counts them. The toast goes away by
    /// itself ``DebugDrawer/toastLifetime`` seconds after the last post, and stays while the
    /// pointer is over it or accessibility focus is on it.
    ///
    /// Each drawer the plugin is registered with, globally or locally, gets the post, as
    /// ``DebugDrawer/postToast(_:fromPlugin:)`` takes it; a plugin no drawer holds
    /// yet posts to ``DebugDrawer/shared``.
    ///
    /// - Parameter message: What the toast says.
    @MainActor func postToast(_ message: String) {
        #if DEBUG
            for drawer in DebugDrawer.drawers(holdingPlugin: id) {
                drawer.postToast(message, fromPlugin: id)
            }
        #endif
    }
}
