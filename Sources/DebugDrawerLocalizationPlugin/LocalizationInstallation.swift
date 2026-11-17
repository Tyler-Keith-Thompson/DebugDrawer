#if DEBUG
    import DebugDrawer

    /// What `Localization.install(mode:)` does in debug builds.
    @MainActor
    enum LocalizationInstallation {
        /// Starts intercepting the app's lookups in `mode`, and registers the plugin over the
        /// app's tables, replacing one installed before.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(
            mode: Localization.Mode,
            source: any LocalizationTableSource = BundleTableSource(appBundles: .main),
            state: LocalizationState = .shared
        ) -> LocalizationModel {
            state.mode = mode
            LocalizationInterception.install()
            let model = LocalizationModel(source: source, state: state, nextLaunchDefaults: .standard) {
                LocalizationRedraw.shared.modeChanged()
            }
            Task { await model.refresh() }
            let plugin = LocalizationPlugin(model: model)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            return model
        }
    }
#endif
