import Foundation

/// The app's files in the debug drawer: its Documents, Library and tmp folders, its bundle and
/// the containers of its app groups, each folder with the total size of what it holds, and each
/// file with its dates and a preview of its text, JSON, property list or image.
///
/// ```swift
/// FileBrowser.install(appGroups: ["group.com.example.orders"])
/// ```
///
/// The type exists in every build, so the call compiles unchanged in release, where it does
/// nothing and reads nothing.
public enum FileBrowser {
    /// Adds the File Browser plugin: in debug builds only; in release it does nothing.
    ///
    /// The plugin lists the app's Documents, Library and tmp folders, its bundle (read-only) and
    /// the shared container of each app group in `appGroups`. A Mac app outside the sandbox shares
    /// those folders with the user's other apps, so there it lists its own folders of Application
    /// Support and Caches (named for its bundle identifier) instead of Documents and Library.
    /// Files can be imported into a folder, renamed, deleted and shared, anywhere but in the
    /// bundle. Nothing is read until the plugin is shown.
    ///
    /// Call it once at startup. Calling it again replaces the plugin.
    ///
    /// - Parameter appGroups: The app group identifiers whose containers to list, as the app's
    ///   entitlements name them (`com.apple.security.application-groups`). A group the system
    ///   gives no container is listed as missing.
    @MainActor
    public static func install(appGroups: [String] = []) {
        #if DEBUG
            FileBrowserInstallation.install(appGroups: appGroups, locations: SystemFileLocations(), fileSystem: LocalFileSystem())
        #endif
    }
}
