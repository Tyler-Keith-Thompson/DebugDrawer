#if DEBUG
    import DebugDrawer
    import Foundation

    /// What `FileBrowser.install(appGroups:)` does in debug builds.
    @MainActor
    enum FileBrowserInstallation {
        /// Registers the plugin over `model`, which lists the containers of `appGroups` from then
        /// on, replacing a plugin installed before. Nothing is read until the plugin is shown.
        ///
        /// - Parameters:
        ///   - appGroups: The app groups whose containers to list.
        ///   - model: The model the plugin shows: the shared one in the app, one over fakes in tests.
        static func install(appGroups: [String], model: FileBrowserModel) {
            let plugin = FileBrowserPlugin(model: model)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            model.setAppGroups(appGroups)
            DebugDrawer.shared.registerGlobal(plugin)
        }
    }
#endif
