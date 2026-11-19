#if DEBUG
    import DebugDrawer

    /// What `UserDefaultsBrowser.install(suites:)` does in debug builds.
    @MainActor
    enum UserDefaultsBrowserInstallation {
        /// Registers the plugin over `model`, which offers `suites` beside the standard defaults
        /// from then on, replacing a plugin installed before. Nothing is read until it is shown.
        ///
        /// - Parameters:
        ///   - suites: The suite names to offer, such as app groups'.
        ///   - model: The model the plugin shows: the shared one in the app, one over fakes in tests.
        static func install(suites: [String], model: UserDefaultsModel) {
            let plugin = UserDefaultsPlugin(model: model)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            model.setSuites(suites)
            DebugDrawer.shared.registerGlobal(plugin)
        }
    }
#endif
