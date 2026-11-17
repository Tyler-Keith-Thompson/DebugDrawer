/// Screen recordings of the app, in the debug drawer: Record and Stop in the drawer and in the
/// floating HUD, the saved movies listed to share or delete, and the newest one added to the bug
/// report.
///
/// The app's own windows are drawn in process on every display frame, so the movie leaves out the
/// drawer, its HUD and its toasts while they stay on screen, and needs no permission: no ReplayKit
/// prompt on iOS, no Screen Recording permission on macOS.
///
/// ```swift
/// ScreenRecording.install()
/// ```
///
/// The type exists in every build, so the call compiles unchanged in release, where it does
/// nothing.
public enum ScreenRecording {
    /// How many recordings are kept unless ``install(capacity:)`` is given another number.
    public static let defaultCapacity = 5

    /// Adds the Screen Recording plugin: in debug builds only; in release it does nothing.
    ///
    /// Recordings saved by earlier launches are listed again. Calling it again replaces the
    /// plugin, keeping a recording in progress, and takes the new capacity.
    ///
    /// - Parameter capacity: How many recordings are kept; once a new one is saved past it, the
    ///   oldest are deleted.
    /// - Precondition: `capacity` is at least 1.
    @MainActor
    public static func install(capacity: Int = defaultCapacity) {
        #if DEBUG
            precondition(capacity > 0, "ScreenRecording keeps at least one recording")
            ScreenRecordingInstallation.install(capacity: capacity)
        #endif
    }
}
