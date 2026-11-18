import Foundation

/// A design mockup laid over the running app, in the debug drawer, to catch pixel drift: the
/// mockup at an opacity, an offset and a scale, normal or in a difference blend, where the pixels
/// that match draw black.
///
/// ```swift
/// // At startup:
/// DesignOverlay.install()
///
/// // On the app's content, beneath .debugDrawer():
/// ContentView()
///     .debugDesignOverlay()
///     .debugDrawer()
/// ```
///
/// The mockup is picked in the drawer: from Photos or Files on iOS, from a file or the pasteboard
/// on macOS. It is kept in `Caches/DebugDrawer/DesignOverlay` (in a Mac app outside the App
/// Sandbox, `Caches/<bundle identifier>/DebugDrawer/DesignOverlay`), so it is there again on the
/// next launch, until Clear. Touches and clicks pass through the mockup to the app, except in Move
/// mode, where a drag moves it.
///
/// The type exists in every build, so the calls compile unchanged in release, where they do
/// nothing.
public enum DesignOverlay {
    /// Adds the Design Overlay plugin: in debug builds only; in release it does nothing.
    ///
    /// The mockup and the settings saved by an earlier launch are read again. Calling it again
    /// replaces the plugin and keeps what it shows.
    ///
    /// - Parameter mockup: The data of an image (PNG, JPEG, HEIC or any format Image I/O reads)
    ///   to show for this launch in place of the saved one, which is kept; `nil` shows the saved
    ///   one. An app's own launch argument can hand it a bundled comp this way.
    /// - Precondition: `mockup` is `nil` or the data of an image.
    @MainActor
    public static func install(mockup: Data? = nil) {
        #if DEBUG
            DesignOverlayInstallation.install(mockup: mockup)
        #endif
    }
}
