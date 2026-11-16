#if DEBUG
    import DebugDrawer
    import Foundation

    /// What `PrivacyPermissions.install()` does in debug builds.
    @MainActor
    enum PrivacyPermissionsInstallation {
        /// Registers the plugin over the permissions `infoDictionary` declares, read through
        /// `authority` and read again on each change `changes` reports, and reads them once now.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(
            infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
            authority: any PermissionAuthority = SystemPermissionAuthority(),
            changes: any PermissionChangeSource = SystemPermissionChangeSource()
        ) -> PermissionsModel {
            let model = PermissionsModel(permissions: DeclaredPermission.declared(in: infoDictionary), authority: authority, changes: changes)
            let plugin = PermissionsPlugin(model: model)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            Task { await model.refresh() }
            return model
        }
    }
#endif
