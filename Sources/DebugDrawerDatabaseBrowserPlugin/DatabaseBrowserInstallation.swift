#if DEBUG
    import DebugDrawer
    import Foundation

    /// What `DatabaseBrowser.install(additionalDirectories:)` does in debug builds.
    @MainActor
    enum DatabaseBrowserInstallation {
        /// Registers the plugin over the stores in `locations` and `additionalDirectories`,
        /// replacing one installed before; the plugin's ``DatabaseBrowserPlugin/install(in:)``
        /// looks for them once now.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(locations: any StoreLocations, additionalDirectories: [URL]) -> DatabaseBrowserModel {
            let model = DatabaseBrowserModel(discovery: StoreDiscovery(locations: locations, additionalDirectories: additionalDirectories))
            let plugin = DatabaseBrowserPlugin(model: model)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            return model
        }
    }
#endif
