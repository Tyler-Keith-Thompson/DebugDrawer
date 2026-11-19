#if DEBUG
    import Combine

    /// The simulation on the main actor, shared by the plugin's view, its HUD and
    /// `debugColorVision()`.
    ///
    /// Main-actor isolated, like the views that read it; nothing reaches it from another thread.
    /// The simulation is not saved: an app that launched gray or with shifted hues, with nothing on
    /// screen to say why, would look broken, so each launch starts with the app's own colors unless
    /// install names a simulation.
    @MainActor
    final class ColorVisionModel: ObservableObject {
        /// The model `ColorVision.install(simulating:)` installs and `debugColorVision()` draws.
        static let shared = ColorVisionModel()

        /// The simulation applied to the app, or `nil` for the app's own colors.
        @Published var simulation: ColorVision.Simulation?

        /// The drawers the plugin is installed in; the last to remove it turns the simulation off.
        private var installations: Set<ObjectIdentifier> = []

        /// Counts `drawer` as one the plugin is installed in.
        func install(in drawer: ObjectIdentifier) {
            installations.insert(drawer)
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, turns the simulation off, so the
        /// app shows its own colors with nothing left to turn it off from.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            simulation = nil
        }

        /// Moves to the next simulation in the order the picker lists them, then back to none.
        func cycle() {
            simulation = ColorVision.Simulation.after(simulation)
        }

        /// Turns `simulation` on, or off if it is the one on.
        func toggle(_ simulation: ColorVision.Simulation) {
            self.simulation = self.simulation == simulation ? nil : simulation
        }
    }
#endif
