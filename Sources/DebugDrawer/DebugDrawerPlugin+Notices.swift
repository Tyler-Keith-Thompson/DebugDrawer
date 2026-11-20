// Badges and toasts are methods on the plugin, which exists in every build, so a plugin's code
// calls them unchanged in release, where the drawer doesn't exist and they do nothing.
public extension DebugDrawerPlugin {
    /// Shows `count` on the plugin's section header in the drawer; zero or less clears it.
    @MainActor func setBadge(_ count: Int) {
        #if DEBUG
            DebugDrawer.shared.setBadge(count, forPlugin: id)
        #endif
    }

    /// Removes the plugin's badge.
    @MainActor func clearBadge() {
        setBadge(0)
    }

    /// Raises a toast while the drawer is closed; tapping it opens the drawer at this plugin.
    /// Posts from one plugin coalesce into one toast that counts them. The toast goes away by
    /// itself ``DebugDrawer/toastLifetime`` seconds after the last post, and stays while the
    /// pointer is over it or accessibility focus is on it.
    @MainActor func postToast(_ message: String) {
        #if DEBUG
            DebugDrawer.shared.postToast(message, fromPlugin: id)
        #endif
    }
}
