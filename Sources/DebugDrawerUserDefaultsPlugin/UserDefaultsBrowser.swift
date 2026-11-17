import Foundation

/// The app's UserDefaults in the debug drawer: the standard defaults and any suites the app names,
/// such as its app groups', each key's value edited in place, keys added and removed, and the list
/// kept current as the app writes.
///
/// ```swift
/// UserDefaultsBrowser.install(suites: ["group.com.example.shared"])
/// ```
///
/// The type exists in every build, so the call compiles unchanged in release, where it does
/// nothing.
public enum UserDefaultsBrowser {
    /// Adds the UserDefaults plugin: in debug builds only; in release it does nothing.
    ///
    /// Calling it again replaces the plugin. Nothing is read until the plugin is first shown.
    ///
    /// - Parameter suites: Suite names to offer beside the standard defaults, such as app group
    ///   identifiers, in the order the picker lists them.
    @MainActor
    public static func install(suites: [String] = []) {
        #if DEBUG
            UserDefaultsBrowserInstallation.install(suites: suites)
        #endif
    }
}
