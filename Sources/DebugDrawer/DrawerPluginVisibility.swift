#if DEBUG
    import SwiftUI

    extension EnvironmentValues {
        /// The drawer whose views these are, told as each plugin's content comes on and leaves the
        /// screen; `nil` outside a drawer, as in a test that draws a section alone. A plugin's view
        /// masks by this drawer's rules (`DebugDrawerRedactionReader`), so a plugin installed in
        /// a `DebugDrawer(defaults:)` of its own follows that drawer rather than the shared one.
        @Entry package var showingDrawer: DebugDrawer?
    }

    extension View {
        /// Tells the drawer in the environment when this view, the content of the plugin with ID
        /// `id`, comes on screen and when it leaves, so the plugin hears
        /// ``DebugDrawerPlugin/didBecomeVisible(in:)`` and ``DebugDrawerPlugin/didBecomeHidden(in:)``.
        func reportsVisibility(ofPlugin id: String) -> some View {
            modifier(DrawerPluginVisibilityReporter(id: id))
        }
    }

    /// What `reportsVisibility(ofPlugin:)` adds.
    private struct DrawerPluginVisibilityReporter: ViewModifier {
        let id: String
        @Environment(\.showingDrawer) private var drawer

        func body(content: Content) -> some View {
            content
                .onAppear { drawer?.pluginContentDidAppear(id: id) }
                .onDisappear { drawer?.pluginContentDidDisappear(id: id) }
        }
    }
#endif
