import SwiftUI

public extension View {
    /// Draws the Design Overlay plugin's mockup over this view: in debug builds only; in release
    /// it returns the view as it is.
    ///
    /// Apply it to the app's content beneath `.debugDrawer()`, so the mockup lies over the app and
    /// under the drawer, its HUD and its toasts, and shows in screenshots and screen recordings of
    /// the app:
    ///
    /// ```swift
    /// ContentView()
    ///     .debugDesignOverlay()
    ///     .debugDrawer()
    /// ```
    ///
    /// The mockup takes no touches or clicks, so the app's controls under it keep working, except
    /// while Move is on in the plugin, when a drag anywhere in the window moves it and a Done
    /// button at the bottom leading corner ends Move.
    func debugDesignOverlay() -> some View {
        #if DEBUG
            modifier(DesignOverlayModifier())
        #else
            self
        #endif
    }
}

#if DEBUG
    // The mockup belongs to the app's content, beneath .debugDrawer(), not to the drawer's chrome
    // (between DrawerChromeBoundary's markers): a screenshot or a recording of the drift is what a
    // bug about it needs, the difference blend has the app beneath it to blend with, and the
    // drawer, its HUD and its toasts stay above the mockup and usable while Move takes the
    // window's touches. Rejected: a hook in core for plugins to draw in the chrome (the mockup
    // would cover the drawer, and the recorder would leave it out), and a UIView or NSView added
    // to the window (a platform view to keep from taking hits, and no SwiftUI blend with the app).

    /// Lays the installed plugin's mockup over the content, and the Move bar over that while Move
    /// is on.
    struct DesignOverlayModifier: ViewModifier {
        @ObservedObject var model = DesignOverlayModel.shared

        func body(content: Content) -> some View {
            content
                .overlay {
                    if let mockup = model.mockup, model.settings.isVisible {
                        DesignOverlayLayer(
                            mockup: mockup,
                            settings: model.settings,
                            isMoving: model.isMoving,
                            move: { model.move(by: $0) }
                        )
                    }
                }
                // At the leading corner: the open drawer covers the trailing edge.
                .overlay(alignment: .bottomLeading) {
                    if model.isMoving {
                        MoveModeBar(offset: model.settings.offset, done: { model.isMoving = false })
                            .padding()
                    }
                }
                // The window's width, edge to edge, which the plugin needs to infer the mockup's
                // scale and to show its size in points.
                .background {
                    Color.clear
                        .ignoresSafeArea()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { model.windowWidth = $0 }
                        .accessibilityHidden(true)
                }
        }
    }
#endif
