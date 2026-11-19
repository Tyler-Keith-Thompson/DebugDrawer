#if DEBUG
    import Foundation

    /// The View Inspector's switches over the app's windows, as a value: what the borders, the
    /// grid, the click indicators and the slowed animations are set to.
    struct ViewInspectorOverlaySettings: Codable, Equatable, Sendable {
        var isBordersEnabled = false
        var isGridEnabled = false
        /// The grid's spacing in points.
        var gridSpacing: Double = 8
        var gridColor: ViewBorderController.GridColor = .blue
        /// The grid's opacity, from 0 to 1.
        var gridOpacity = 0.15
        var isClickIndicatorEnabled = false
        /// How many times slower animations run: 1 is the windows' own speed.
        var animationSpeed: Double = 1
    }
#endif
