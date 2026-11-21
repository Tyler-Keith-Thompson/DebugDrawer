import DebugDrawer
import SwiftUI

// The Network plugin's body for a viewer of another app's requests, over a connection the viewer
// holds: a sidecar's socket or store, or a device paired over the network (`DebugDrawerRemote`).
// It waits for the app's model as it appears, then draws what the plugin draws in the app.
// Rejected: a public initializer over `DebugDrawerPluginTransport` (`NetworkPlugin(transport:)`
// already takes one, and a viewer holds the connection, not a plugin transport).

/// The Network plugin's view of the requests of an app at the other end of a
/// `DebugDrawerTransport`: its log, mocks, conditions and ignored hosts, as the drawer shows them
/// there, with each command sent to the app.
///
/// ```swift
/// let device = DebugDrawerNetworkTransport(endpoint: found.endpoint, viewerName: "Studio Mac")
/// try await device.pair(code: typedCode)
/// // In a view's body:
/// NetworkPluginView(transport: device)
/// ```
///
/// It shows "Waiting for Network…" until the app's ``NetworkModel`` sends its first snapshot,
/// and why it wasn't reached when the connection fails. It intercepts nothing in this process.
/// Release builds draw nothing.
public struct NetworkPluginView: View {
    #if DEBUG
        /// The connection to the app's model, made once for the view's lifetime.
        @StateObject var connection: DebugDrawerPluginConnection<NetworkSnapshot, NetworkCommand>
        let inspection = Inspection<Self>()

        /// The view over `transport`: it connects to the model the app registered under
        /// ``NetworkPlugin``'s ID as it appears.
        ///
        /// - Parameter transport: The connection to the app's models: a sidecar's, or a
        ///   `DebugDrawerNetworkTransport` once paired. The view holds it while it lives.
        public init(transport: any DebugDrawerTransport) {
            _connection = StateObject(wrappedValue: DebugDrawerPluginConnection(transport: transport, pluginID: NetworkPlugin().id))
        }

        public var body: some View {
            DebugDrawerPluginConnectionView(connection, title: NetworkPlugin().title) { transport in
                NetworkPluginContent(transport: transport)
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }
    #else
        /// The view over `transport`; release builds draw nothing.
        ///
        /// - Parameter transport: Ignored.
        public init(transport: any DebugDrawerTransport) {}

        public var body: some View {
            EmptyView()
        }
    #endif
}
