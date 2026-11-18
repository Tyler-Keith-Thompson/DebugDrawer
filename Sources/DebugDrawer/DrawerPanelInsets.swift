#if DEBUG
    import SwiftUI

    extension EdgeInsets {
        /// The margin around the drawer's panel inside the window's safe area, which the panel
        /// keeps clear of: the status bar, the home indicator, a landscape notch and the keyboard,
        /// so the filter bar at the panel's foot stays above the keyboard.
        ///
        /// - Parameter layout: The panel's width class. A regular panel leaves its leading edge
        ///   open; a compact one, as wide as the window, keeps the margin there too.
        /// - Returns: The panel's padding.
        static func drawerPanel(layout: DrawerPanelLayout) -> EdgeInsets {
            let margin: CGFloat = 8
            return EdgeInsets(top: margin, leading: layout == .compact ? margin : 0, bottom: margin, trailing: margin)
        }
    }
#endif
