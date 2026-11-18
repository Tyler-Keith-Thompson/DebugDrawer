// Built wherever the drawer is, though only iOS draws it (DebugDrawerOverlay): its view tests run
// on the Mac, where ViewInspector does.
#if DEBUG
    import SwiftUI

    /// What the compact panel leaves of the app, dimmed: a tap on it closes the drawer, as one
    /// outside a sheet dismisses it.
    struct DrawerBackdrop: View {
        let close: () -> Void

        var body: some View {
            DrawerPalette.backdrop
                .contentShape(Rectangle())
                .onTapGesture(perform: close)
                .accessibilityElement()
                .accessibilityLabel("Close the debug drawer")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default, close)
                // Last, so the tap target spans the status bar and home indicator strips it dims.
                .ignoresSafeArea()
        }
    }
#endif
