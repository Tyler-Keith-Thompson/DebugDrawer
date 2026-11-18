#if DEBUG
    import SwiftUI

    extension EdgeInsets {
        /// The margin around the drawer's panel inside the window's safe area, which the panel
        /// keeps clear of: the status bar, the home indicator, a landscape notch and the keyboard,
        /// so the filter bar at the panel's foot stays above the keyboard.
        ///
        /// - Parameter layout: The panel's width class. A regular panel leaves its leading edge
        ///   open; a compact one, as wide as the window, keeps the margin there too, and leaves a
        ///   strip of the app above it, which its backdrop dims and a tap on closes the drawer.
        /// - Returns: The panel's padding.
        static func drawerPanel(layout: DrawerPanelLayout) -> EdgeInsets {
            let margin: CGFloat = 8
            switch layout {
            case .regular:
                return EdgeInsets(top: margin, leading: 0, bottom: margin, trailing: margin)
            case .compact:
                // The system keeps taps on the status bar, so the strip is what the safe area
                // leaves below it (8 points on a Face ID iPhone) and this: 44 points in all,
                // Apple's smallest tap target (DrawerCloseButton.minimumTapSize).
                let strip: CGFloat = 36
                return EdgeInsets(top: strip, leading: margin, bottom: margin, trailing: margin)
            }
        }
    }
#endif
