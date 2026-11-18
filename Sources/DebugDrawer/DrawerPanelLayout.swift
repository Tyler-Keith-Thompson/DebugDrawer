import CoreGraphics

/// How wide the drawer's panel is, chosen from the width of the window it opens in.
enum DrawerPanelLayout: Equatable {
    /// A panel ``regularWidth`` wide along the window's trailing edge, beside the app.
    case regular
    /// A panel as wide as the window, for a window too narrow to keep much of the app beside a
    /// regular panel (an iPhone in portrait, an iPad app in Slide Over, a narrow Mac window). It
    /// opens at the list of plugins and shows each one alone.
    case compact

    /// A regular panel's width: what an iPhone in landscape, an iPad and a Mac window leave the app
    /// beside it, as Xcode's inspector is.
    static let regularWidth: CGFloat = 316 * .debugDrawerTextScale

    /// The layout for a window `width` points wide: compact when a regular panel would cover more
    /// than half of it.
    ///
    /// - Parameter width: The window's width, in points.
    init(windowWidth width: CGFloat) {
        self = width < Self.regularWidth * 2 ? .compact : .regular
    }
}

/// What the open drawer shows: the outline of every plugin, or one plugin alone at the panel's
/// full height, as Xcode's focus on one item of a navigator.
enum DrawerNavigation: Hashable {
    /// Every plugin, in its sections, under the navigator tabs.
    case outline
    /// The plugin with this ID, alone.
    case plugin(String)

    /// The ID of the plugin shown alone, or `nil` in the outline.
    var pluginID: String? {
        switch self {
        case .outline: nil
        case let .plugin(id): id
        }
    }
}
