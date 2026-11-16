#if DEBUG
    import SwiftUI

    extension EdgeInsets {
        /// The space around the drawer's panel: the window's safe area (status bar, home indicator,
        /// a landscape notch), and never less than a small margin from the window's edge.
        ///
        /// - Parameter safeArea: The safe-area insets of the window the drawer covers.
        /// - Returns: The panel's top, bottom and trailing padding; the leading edge is open space.
        static func drawerPanel(safeArea: EdgeInsets) -> EdgeInsets {
            let margin: CGFloat = 8
            return EdgeInsets(top: Swift.max(margin, safeArea.top), leading: 0,
                              bottom: Swift.max(margin, safeArea.bottom),
                              trailing: Swift.max(margin, safeArea.trailing))
        }
    }
#endif
