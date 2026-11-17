import Foundation

/// The app's state cleared from the debug drawer, as deleting the app and installing it again
/// would leave it: UserDefaults, keychain items, the files in the app's containers, caches,
/// cookies, the URL cache, and any cleanup of the app's own.
///
/// ```swift
/// AppStateReset.install()
/// ```
///
/// Each category is a checkbox with what it will delete beside it. Reset shows exactly what
/// goes, item by item, before anything is deleted, then what was cleared and what couldn't be.
/// Reset and Relaunch starts the app again on macOS; elsewhere an app can't relaunch itself, so
/// it quits, to be opened again from the Home Screen.
///
/// The type exists in every build, so the call compiles unchanged in release, where it does
/// nothing.
public enum AppStateReset {
    /// Cleanup of the app's own, run first when its category is selected, before any file is
    /// deleted, such as closing a database the app holds open, or clearing what the app keeps in
    /// memory.
    public struct Cleanup: Sendable {
        /// What the cleanup clears, as the drawer lists it ("Close the orders database").
        public let title: String
        let perform: @MainActor @Sendable () async throws -> Void

        /// - Parameters:
        ///   - title: What the cleanup clears, as the drawer lists it.
        ///   - perform: The cleanup. An error it throws is shown with the reset's results.
        public init(_ title: String, perform: @escaping @MainActor @Sendable () async throws -> Void) {
            self.title = title
            self.perform = perform
        }
    }

    /// Adds the Reset App State plugin: in debug builds only; in release it does nothing.
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
