#if DEBUG
    import DebugDrawer
    import Foundation

    /// What `FileBrowser.install(appGroups:)` does in debug builds.
    @MainActor
    enum FileBrowserInstallation {
        /// Registers the plugin over the folders in `locations` and the containers of `appGroups`,
        /// replacing one installed before. Nothing is read until the plugin is shown.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(appGroups: [String], locations: any FileLocations, fileSystem: any FileSystem) -> FileBrowserModel {
            let model = FileBrowserModel(roots: FileRoots(locations: locations, appGroups: appGroups), fileSystem: fileSystem)
            let plugin = FileBrowserPlugin(model: model)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            return model
        }
    }
#endif
