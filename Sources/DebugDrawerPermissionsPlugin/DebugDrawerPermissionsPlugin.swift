#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The permissions `PrivacyPermissions.install()` found declared, each with its live status,
    /// a Request button while the user hasn't decided and an Open Settings button.
    public struct PermissionsPlugin: DebugDrawerPlugin {
        public var id: String {
            "PermissionsPlugin"
        }

        public var title = "Permissions"
        public var category = "App"
        public var icon = "lock.shield"

        let model: PermissionsModel

        init(model: PermissionsModel) {
            self.model = model
        }

        public var body: some View {
            PermissionsPluginView(model: model)
        }
    }

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
