import Foundation

// Public because it is `ViewInspectorModel`'s `Snapshot`, and opaque: its fields stay internal, so
// the plugin's types (a view node, a render count) don't become API. A reader outside the module
// carries it whole, encoded. It holds values read from the app's views, never a view or window:
// those stay behind the model's services.

#if DEBUG
    /// Everything the View Inspector plugin shows, as a value: the overlay switches, the render
    /// counts and whether tracked views flash, and the view hierarchy snapshot, when one is open.
    ///
    /// ``ViewInspectorModel`` makes it; the plugin's view draws it. It is `Codable`, so a
    /// transport can carry it.
    public struct ViewInspectorSnapshot: Codable, Equatable, Sendable {
        /// The borders, the grid, the click indicators and the animation speed.
        var overlays = ViewInspectorOverlaySettings()
        /// Whether tracked views flash their frame on each render.
        var isFlashingRenders = false
        /// Every tracked name and its render count, busiest first.
        var renderCounts: [RenderTracker.Entry] = []
        /// The key window's hierarchy as last read, or `nil` when it is collapsed.
        var hierarchy: ViewNode?
    }
#else
    /// Release builds inspect nothing: this stand-in holds nothing.
    public struct ViewInspectorSnapshot: Codable, Equatable, Sendable {}
#endif
