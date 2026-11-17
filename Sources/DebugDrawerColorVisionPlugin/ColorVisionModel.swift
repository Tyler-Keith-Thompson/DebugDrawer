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
