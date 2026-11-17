import SwiftUI

public extension View {
    /// Draws this view through the Color Vision plugin's simulation: in debug builds only; in
    /// release it returns the view as it is.
    ///
    /// Apply it to the views whose colors carry meaning, such as a status, a chart or a card, or
    /// to a whole screen that SwiftUI draws itself. Every view it is applied to follows the
    /// simulation picked in the drawer, which keeps its own colors:
    ///
    /// ```swift
    /// OrderStatusView(order: order)
    ///     .debugColorVision()
    /// ```
    ///
    /// The simulation runs as a Metal shader over what SwiftUI draws, so a view backed by UIKit or
    /// AppKit inside it (`List`, `Form`, `NavigationStack` on iOS, `ScrollView` on macOS, text
    /// fields, maps, web views) shows SwiftUI's placeholder while a simulation is on. Apply the
    /// modifier to the content inside such a view instead, such as a list's rows.
    ///
    /// With no simulation on, the view draws exactly as it would without the modifier. Turning a
    /// simulation on or off draws the view anew, so the `@State` inside it starts over.
    func debugColorVision() -> some View {
        #if DEBUG
            modifier(ColorVisionModifier())
        #else
            self
        #endif
    }
}

#if DEBUG
    // Where the simulation goes: on the app's content, never on the drawer, which keeps true color
    // so its picker and the HUD that turn the simulation off stay readable, and its HUD and toasts
    // stay as they are. Not beneath .debugDrawer() over the whole app, as Design Overlay's mockup
    // is: SwiftUI draws a view that UIKit or AppKit backs as a placeholder under any shader effect,
    // a disabled one included, and on iOS NavigationStack and List are such views, so a modifier at
    // the root would blank most apps. Rejected: the whole window filtered (no public API filters a
    // UIKit window's layers live), and SwiftUI's `_colorMatrix(_:)`, which does reach UIKit and
    // AppKit views but is an undocumented symbol and works on encoded, not linear, color.

    /// Applies the installed plugin's simulation to the content.
    struct ColorVisionModifier: ViewModifier {
        @ObservedObject var model = ColorVisionModel.shared

        func body(content: Content) -> some View {
            content.colorVisionSimulation(model.simulation)
        }
    }
#endif
