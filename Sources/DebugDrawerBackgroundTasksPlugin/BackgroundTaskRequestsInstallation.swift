#if DEBUG
    import DebugDrawer
    import Foundation

    /// What `BackgroundTaskRequests.install()` does in debug builds.
    @MainActor
    enum BackgroundTaskRequestsInstallation {
        /// Registers the plugin over what `infoDictionary` declares, read through `client` and
        /// read again on each change `changes` reports, and reads it once now.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(
            infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
            client: any BackgroundTaskSchedulerClient,
            changes: any BackgroundTaskChangeSource = AppActivationChangeSource()
        ) -> BackgroundTasksModel {
            // Before the new model observes anything: removing the plugin installed before
            // uninstalls it, which stops its own model.
            DebugDrawer.shared.unregisterGlobal(id: BackgroundTasksPlugin.pluginID)
            let model = BackgroundTasksModel(
                declaration: BackgroundTaskDeclaration(infoDictionary: infoDictionary), client: client, changes: changes
            )
            let plugin = BackgroundTasksPlugin(model: model)
            DebugDrawer.shared.registerGlobal(plugin)
            Task { await model.refresh() }
            return model
        }
    }
#endif
