import SwiftUI

public extension View {
    /// Pads a row a plugin lays out itself above and below by as much as the drawer's own rows
    /// (``DebugDrawerRow`` and the others), so it stacks among them with no spacing: 6 points on
    /// iOS and 3 on the Mac at the default text size, growing with the text.
    ///
    /// In release it changes nothing, so a caller compiles unchanged.
    func debugDrawerRowPadding() -> some View {
        #if DEBUG
            modifier(DrawerRowPadding())
        #else
            self
        #endif
    }
}

#if DEBUG
    /// The padding `debugDrawerRowPadding()` gives a row.
    struct DrawerRowPadding: ViewModifier {
        @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.rowPadding

        func body(content: Content) -> some View {
            content.padding(.vertical, padding)
        }
    }
#endif
