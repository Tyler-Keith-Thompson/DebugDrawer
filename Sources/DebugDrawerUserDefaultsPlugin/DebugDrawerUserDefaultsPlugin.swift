import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The app's UserDefaults: a picker of the suites, the shown suite's keys with a filter, each
/// value edited in place whatever its type, and keys added and deleted. Installed by
/// ``UserDefaultsBrowser/install(suites:)``.
public struct UserDefaultsPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "UserDefaultsPlugin"
    }

    public var title = "UserDefaults"
    public var category = "Storage"
    public var icon = "cylinder.split.1x2"

    #if DEBUG
        /// The model the plugin shows: the shared one in the app, one over fakes in tests.
        let model: UserDefaultsModel

        init(model: UserDefaultsModel) {
            self.model = model
        }
    #endif

    public var body: some View {
        #if DEBUG
            UserDefaultsPluginView(transport: .direct(to: model))
        #else
            EmptyView()
        #endif
    }

    /// Counts `drawer` as one that holds the plugin; nothing is read until it is shown.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            model.install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, stops observing the defaults'
    /// changes and drops the keys it read. The defaults themselves are untouched.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            model.uninstall(from: ObjectIdentifier(drawer))
        #endif
    }

    /// How many keys the filters let through ("12 keys").
    public var headerAccessory: some View {
        #if DEBUG
            UserDefaultsHeaderAccessory(transport: .direct(to: model))
        #else
            EmptyView()
        #endif
    }
}
