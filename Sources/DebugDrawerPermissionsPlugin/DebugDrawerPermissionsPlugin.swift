import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The permissions `PrivacyPermissions.install()` found declared, each with its live status,
/// a Request button while the user hasn't decided and an Open Settings button.
public struct PermissionsPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer.
    static let pluginID = "PermissionsPlugin"

    public var id: String {
        Self.pluginID
    }

    public var title = "Permissions"
    public var category = "App"
    public var icon = "lock.shield"

    #if DEBUG
        let model: PermissionsModel

        init(model: PermissionsModel) {
            self.model = model
        }
    #endif

    public var body: some View {
        #if DEBUG
            PermissionsPluginView(model: model)
        #else
            EmptyView()
        #endif
    }

    /// Reads every status again on each change from now on, if an uninstall stopped it. Release
    /// builds read nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            model.install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once no drawer has the plugin, stops observing the app becoming active and Location's
    /// authorization, drops the statuses read, and lets go of the Location and Bluetooth managers.
    /// A request still waiting for the user's answer returns.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            model.uninstall(from: ObjectIdentifier(drawer))
        #endif
    }
}

#if DEBUG
    /// Reads the model and hands its rows to `PermissionsView`; requests run on the model and
    /// Open Settings goes through the environment's `openURL`.
    struct PermissionsPluginView: View {
        @ObservedObject var model: PermissionsModel
        @Environment(\.openURL) private var openURL

        var body: some View {
            PermissionsView(
                rows: model.rows,
                onRequest: { kind in
                    Task { await model.request(kind) }
                },
                onOpenSettings: { kind in
                    guard let url = kind.settingsURL else { return }
                    openURL(url)
                }
            )
        }
    }
#endif
