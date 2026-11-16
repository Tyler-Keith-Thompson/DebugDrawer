#if DEBUG
    import DebugDrawer

    /// What `AnalyticsEvents.install(capacity:)` does in debug builds.
    @MainActor
    enum AnalyticsEventsInstallation {
        /// Registers the plugin over `log`, kept to `capacity` events, replacing one installed
        /// before; the events already kept stay.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(capacity: Int, log: AnalyticsEventLog = .shared) -> AnalyticsEventsModel {
            log.resize(to: capacity)
            let model = AnalyticsEventsModel(log: log) { count in
                DebugDrawer.shared.setBadge(count, forPlugin: AnalyticsPlugin.pluginID)
            }
            let plugin = AnalyticsPlugin(model: model)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            return model
        }
    }
#endif
