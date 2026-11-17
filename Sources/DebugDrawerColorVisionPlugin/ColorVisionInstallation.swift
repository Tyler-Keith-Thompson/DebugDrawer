#if DEBUG
    import DebugDrawer

    /// What `ColorVision.install(simulating:)` does in debug builds.
    @MainActor
    enum ColorVisionInstallation {
        /// Sets `model`'s simulation and registers the plugin over it, replacing one installed
        /// before.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(simulating simulation: ColorVision.Simulation?, model: ColorVisionModel = .shared) -> ColorVisionModel {
            model.simulation = simulation
            let plugin = ColorVisionPlugin(model: model)
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            DebugDrawer.shared.registerGlobal(plugin)
            return model
        }
    }
#endif
