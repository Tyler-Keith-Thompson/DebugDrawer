#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Draws the Deep Link Tester from its model's snapshot, through a transport, and sends it
    /// what the user does; `DeepLinkForm` draws the values.
    struct DeepLinkPluginView: View {
        @StateObject private var transport: DebugDrawerPluginTransport<DeepLinkSnapshot, DeepLinkCommand>

        /// - Parameter transport: Joins the view to the model; the plugin passes
        ///   `.direct(to: model)`.
        init(transport: @escaping @autoclosure () -> DebugDrawerPluginTransport<DeepLinkSnapshot, DeepLinkCommand>) {
            _transport = StateObject(wrappedValue: transport())
        }

        var body: some View {
            let snapshot = transport.snapshot
            DeepLinkForm(
                urlText: Binding(get: { transport.snapshot.urlText }, set: { send(.setURLText($0)) }),
                outcome: snapshot.outcome,
                presets: snapshot.presets,
                history: snapshot.history,
                activities: snapshot.activities,
                onOpen: { send(.open($0)) },
                onContinue: { send(.continue($0)) },
                onClear: { send(.clearHistory) }
            )
        }

        private func send(_ action: DeepLinkCommand.Action) {
            transport.send(DeepLinkCommand(action))
        }
    }
#endif
