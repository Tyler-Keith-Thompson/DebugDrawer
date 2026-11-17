import SwiftUI

public extension View {
    /// Draws the view again whenever the Localization plugin's mode changes, so strings it looked
    /// up before the change show the new mode: in debug builds only; in release it returns the
    /// view as it is.
    ///
    /// The view gets a new identity on each change, so the `@State` inside it, its scroll
    /// positions and navigation start over. Apply it to the app's content beneath
    /// `.debugDrawer()`, so the drawer itself keeps its place:
    ///
    /// ```swift
    /// ContentView()
    ///     .debugLocalization()
    ///     .debugDrawer()
    /// ```
    ///
    /// Without it a mode applies to each string the next time the app looks it up.
    func debugLocalization() -> some View {
        #if DEBUG
            modifier(LocalizationRedrawModifier())
        #else
            self
        #endif
    }
}

#if DEBUG
    /// Gives the content the count of mode changes as its identity.
    private struct LocalizationRedrawModifier: ViewModifier {
        @ObservedObject private var redraw = LocalizationRedraw.shared

        func body(content: Content) -> some View {
            // A new identity rather than an environment value: a view that read a string through
            // NSLocalizedString in its body reads no environment value a change could invalidate,
            // so only rebuilding it reads the string again.
            content.id(redraw.generation)
        }
    }
#endif
