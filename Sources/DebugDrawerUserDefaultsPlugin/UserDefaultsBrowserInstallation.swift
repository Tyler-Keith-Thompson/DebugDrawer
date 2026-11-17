#if DEBUG
    import DebugDrawer

    /// What `UserDefaultsBrowser.install(suites:)` does in debug builds.
    @MainActor
    enum UserDefaultsBrowserInstallation {
        /// Registers the plugin over the suites, replacing one installed before.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(suites: [String], storage: any UserDefaultsStorage = _UserDefaultsStorage()) -> UserDefaultsModel {
            let model = UserDefaultsModel(suites: suites, storage: storage)
            let plugin = UserDefaultsPlugin(model: model)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            return model
        }
    }
#endif
