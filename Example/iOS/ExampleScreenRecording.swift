import DebugDrawer
import DebugDrawerScreenRecordingPlugin
import Foundation

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The example's screen recordings: the plugin installed, and its Record button pinned to the HUD
/// on request.
enum ExampleScreenRecording {
    /// Launched with this argument, the app pins Screen Recording's Record button to the HUD, so a
    /// recording can be started and stopped with the drawer closed, and checked without a hand.
    static let launchArgument = "-PinScreenRecordingToHUD"

    /// Installs the plugin, which compiles in release too and does nothing there.
    @MainActor
    static func install() {
        ScreenRecording.install()
        #if DEBUG
            // The plugin's ID is its type's name, as for every plugin that declares none.
            let pluginID = "ScreenRecordingPlugin"
            if ProcessInfo.processInfo.arguments.contains(launchArgument), !DebugDrawer.shared.hudLayout.pinned.contains(pluginID) {
                DebugDrawer.shared.toggleHUD(forPlugin: pluginID)
            }
        #endif
    }
}
