/// The app's privacy permissions in the debug drawer: each one its Info.plist declares a usage
/// description for, with its status as the system reports it now.
///
/// The type exists in every build, so the call compiles unchanged in release, where it does
/// nothing and the plugin references none of the frameworks that read a permission's status.
public enum PrivacyPermissions {
    /// Adds the Permissions plugin: in debug builds only; in release it does nothing.
    ///
    /// The plugin lists every permission the main bundle's Info.plist has a usage description
    /// for (`NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription` and so on), and
    /// notifications, which need none. Each shows its status, read again whenever the app becomes
    /// active (as it does on coming back from Settings), when Location reports a
    /// change and after a request; a Request button while the user hasn't decided, which shows
    /// the system's prompt; and an Open Settings button. Reading a status never prompts.
    ///
    /// Call it once at startup. Calling it again replaces the plugin with one that reads the
    /// Info.plist again.
    @MainActor
    public static func install() {
        #if DEBUG
            PrivacyPermissionsInstallation.install()
        #endif
    }
}
