import DebugDrawerAppStateReset
import Foundation

extension AppStateReset {
    /// Adds the Reset App State plugin: in debug builds only; in release it does nothing.
    ///
    /// Each category is a checkbox with what it will delete beside it. Reset shows exactly what
    /// goes, item by item, before anything is deleted, then what was cleared and what couldn't be.
    /// Reset and Relaunch starts the app again on macOS; elsewhere an app can't relaunch itself, so
    /// it quits, to be opened again from the Home Screen.
    ///
    /// ```swift
    /// AppStateReset.install()
    /// ```
    ///
    /// The app groups the app's entitlements name are found on their own. Calling it again
    /// replaces the plugin.
    ///
    /// - Parameters:
    ///   - appGroups: App group identifiers to clear beyond those the entitlements name: each
    ///     group's UserDefaults suite, its container's files and its caches.
    ///   - directories: Directories beyond the app's containers whose contents count as the app's
    ///     files. Their contents are deleted; the directories themselves are kept.
    ///   - cleanup: Cleanup of the app's own, offered as a category of its own; `nil` for none.
    @MainActor
    public static func install(appGroups: [String] = [], directories: [URL] = [], cleanup: Cleanup? = nil) {
        #if DEBUG
            AppStateResetInstallation.install(appGroups: appGroups, directories: directories, cleanup: cleanup)
        #endif
    }
}
