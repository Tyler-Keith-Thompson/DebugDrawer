#if DEBUG
    import DebugDrawer

    /// What `ColorVision.install(simulating:)` does in debug builds.
    @MainActor
    enum ColorVisionInstallation {
        /// Removes a plugin installed before, then sets `model`'s simulation and registers the
        /// plugin over it.
        ///
        /// - Returns: The plugin's model.
        @discardableResult
        static func install(simulating simulation: ColorVision.Simulation?, model: ColorVisionModel = .shared) -> ColorVisionModel {
            let plugin = ColorVisionPlugin(model: model)
            // First, so the old plugin's uninstall can't turn off the simulation set here.
            DebugDrawer.shared.unregisterGlobal(id: plugin.id)
            model.simulation = simulation
            DebugDrawer.shared.registerGlobal(plugin)
            return model
        }
    }
#endif
