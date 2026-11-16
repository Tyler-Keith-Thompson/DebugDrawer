import SwiftUI

public extension View {
    /// Draws this view as the selected item of a list, the way ``DebugDrawerStackFrameRow`` draws
    /// its selected frame: on the selection fill, with the text it colors with
    /// `debugDrawerForegroundStyle(_:)` in the colors that read on that fill.
    ///
    /// - Parameter isSelected: Whether the view is selected; when `false` it changes nothing.
    ///
    /// In release it changes nothing, so a caller compiles unchanged.
    func debugDrawerSelected(_ isSelected: Bool) -> some View {
        #if DEBUG
            environment(\.debugDrawerIsSelected, isSelected)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: DrawerSpacing.badgeRadius).fill(DrawerPalette.selection)
                    }
                }
        #else
            self
        #endif
    }
}

#if DEBUG
    extension EnvironmentValues {
        /// Whether the view sits on the selection fill (`debugDrawerSelected(_:)`), so its text
        /// takes the colors that read on it.
        @Entry var debugDrawerIsSelected = false
    }
#endif
