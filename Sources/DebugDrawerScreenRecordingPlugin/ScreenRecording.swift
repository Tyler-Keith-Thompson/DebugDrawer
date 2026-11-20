import DebugDrawer

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

    /// Adds the Screen Recording plugin to `DebugDrawer.shared`: in debug builds only; in release
    /// it does nothing.
    ///
    /// The same as ``install(capacity:in:)`` with the shared drawer.
    ///
    /// - Parameter capacity: How many recordings are kept; once a new one is saved past it, the
    ///   oldest are deleted.
    /// - Precondition: `capacity` is at least 1.
    @MainActor
    public static func install(capacity: Int = defaultCapacity) {
        install(capacity: capacity, in: .shared)
    }

    /// Adds the Screen Recording plugin to `drawer`: in debug builds only; in release it does
    /// nothing.
    ///
    /// The recorder, the list of recordings, which of them the bug report carries, the capacity
    /// and the Show Touches setting are `drawer`'s own (Show Touches is kept in its defaults), so
    /// a drawer made with `DebugDrawer(defaults:)` for a test records apart from
    /// `DebugDrawer.shared`. The movies are saved in the app's one recordings folder, which every
    /// drawer lists.
    ///
    /// Recordings saved by earlier launches are listed again. Calling it again with the same
    /// drawer keeps the plugin and a recording in progress, and takes the new capacity.
    ///
    /// ```swift
    /// let drawer = DebugDrawer(defaults: UserDefaults(suiteName: "ScreenRecordingTests")!)
    /// ScreenRecording.install(in: drawer)
    /// ```
    ///
    /// - Parameters:
    ///   - capacity: How many recordings are kept; once a new one is saved past it, the oldest
    ///     are deleted.
    ///   - drawer: The drawer to add the plugin to, which keeps its state.
    /// - Precondition: `capacity` is at least 1.
    @MainActor
    public static func install(capacity: Int = defaultCapacity, in drawer: DebugDrawer) {
        #if DEBUG
            precondition(capacity > 0, "ScreenRecording keeps at least one recording")
            ScreenRecordingInstallation.install(capacity: capacity, in: drawer)
        #endif
    }
}
