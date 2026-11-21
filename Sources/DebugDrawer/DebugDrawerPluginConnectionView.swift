#if DEBUG
    import SwiftUI

    /// A plugin's view over a ``DebugDrawerPluginConnection``: "Waiting for Network…" until the
    /// model's first snapshot is in, then the content over the plugin transport, or why the model
    /// wasn't reached.
    ///
    /// It connects as it appears; a view that goes before the model answers stops waiting, and
    /// connects again when it comes back.
    package struct DebugDrawerPluginConnectionView<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable, Content: View>: View {
        @ObservedObject private var connection: DebugDrawerPluginConnection<Snapshot, Command>
        private let title: String
        private let content: (DebugDrawerPluginTransport<Snapshot, Command>) -> Content

        /// - Parameters:
        ///   - connection: The connection to show; the caller holds it, for the view's lifetime.
        ///   - title: The plugin's name, as the waiting and failed states say it.
        ///   - content: The plugin's view over the transport, once connected.
        package init(
            _ connection: DebugDrawerPluginConnection<Snapshot, Command>,
            title: String,
            @ViewBuilder content: @escaping (DebugDrawerPluginTransport<Snapshot, Command>) -> Content
        ) {
            self.connection = connection
            self.title = title
            self.content = content
        }

        package var body: some View {
            switch connection.state {
            case .connecting:
                ProgressView("Waiting for \(title)…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
                    // Cancelled as the view goes, which ends the wait.
                    .task { await connection.connect() }
            case let .connected(transport):
                content(transport)
            case let .failed(error):
                DebugDrawerEmptyState("\(title) Not Reached", systemImage: "exclamationmark.triangle") {
                    Text(error.localizedDescription)
                }
            }
        }
    }
#endif
