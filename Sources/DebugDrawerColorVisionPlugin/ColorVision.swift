/// Color vision deficiencies and grayscale simulated over the running app, in the debug drawer,
/// so a designer can check what carries meaning by color alone: a red error that reads like a
/// green success, a chart whose series merge.
///
/// ```swift
/// // At startup:
/// ColorVision.install()
///
/// // On the views whose colors carry meaning:
/// OrderStatusView(order: order)
///     .debugColorVision()
/// ```
///
/// A simulation is picked in the drawer or cycled from the HUD, and applies live to every view
/// under `.debugColorVision()`; the drawer, its HUD and its toasts keep their own colors. Each
/// launch starts with none, unless `install(simulating:)` names one.
///
/// The type exists in every build, so the calls compile unchanged in release, where they do
/// nothing.
public enum ColorVision {
    /// How the app's colors are simulated.
    public enum Simulation: String, CaseIterable, Sendable {
        /// No long-wavelength (red) cones: reds dim and fall in with greens.
        case protanopia
        /// No medium-wavelength (green) cones: reds and greens look alike.
        case deuteranopia
        /// No short-wavelength (blue) cones: blues turn teal and yellows pink.
        case tritanopia
        /// Luminance alone, with no hue at all.
        case grayscale
    }

    /// Adds the Color Vision plugin: in debug builds only; in release it does nothing.
    ///
    /// Calling it again replaces the plugin and sets the simulation.
    ///
    /// - Parameter simulation: The simulation the app starts in, such as one a launch argument of
    ///   the app's own names; `nil` starts with the app's own colors.
    @MainActor
    public static func install(simulating simulation: Simulation? = nil) {
        #if DEBUG
            ColorVisionInstallation.install(simulating: simulation)
        #endif
    }
}
