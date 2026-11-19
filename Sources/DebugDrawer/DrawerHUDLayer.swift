#if DEBUG
    import SwiftUI

    /// The pinned plugins' HUD, if any are pinned, faded out while a capture hides it.
    ///
    /// On the Mac it is drawn in a panel of the drawer's own (DrawerChromePanel), on iOS in a
    /// window of the drawer's own (DrawerChromeWindow), and elsewhere by `debugDrawer()` over the
    /// app's view.
    struct DrawerHUDLayer: View {
        @ObservedObject var drawer: DebugDrawer
        /// Called with the card's frame, in global coordinates, as it moves, and `nil` once it
        /// has gone.
        var cardFrameDidChange: (CGRect?) -> Void = { _ in }

        var body: some View {
            let readouts = drawer.hudPlugins
            if !readouts.isEmpty {
                DrawerHUDView(
                    readouts: readouts,
                    origin: drawer.hudLayout.origin,
                    move: { drawer.moveHUD(to: $0) },
                    unpin: { drawer.toggleHUD(forPlugin: $0) },
                    cardFrameDidChange: cardFrameDidChange
                )
                .opacity(drawer.isHUDHidden ? 0 : 1)
                .environment(\.showingDrawer, drawer)
                .onDisappear { cardFrameDidChange(nil) }
            }
        }
    }
#endif
