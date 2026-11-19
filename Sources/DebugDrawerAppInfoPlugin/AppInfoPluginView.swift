#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the facts, worded from ``AppInfoModel``'s snapshot. Showing it reads
    /// nothing by itself: the drawer that shows it starts the model through the plugin's lifecycle
    /// hooks.
    ///
    /// It draws the model's snapshots from its transport and sends it a refresh when asked;
    /// Copy Info copies the text the view words.
    struct AppInfoPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<AppInfoSnapshot, AppInfoCommand>

        /// - Parameter transport: Joins the view to the model; made once, for the view's lifetime.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<AppInfoSnapshot, AppInfoCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            AppInfoFactsView(facts: AppInfoFacts(snapshot: transport.snapshot)) {
                transport.send(AppInfoCommand(.refresh))
            }
        }
    }
#endif
