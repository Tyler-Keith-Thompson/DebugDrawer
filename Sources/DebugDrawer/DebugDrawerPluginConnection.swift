import Combine

// A plugin's view over a `DebugDrawerTransport` rather than over a plugin transport already made:
// `connect(toPlugin:snapshot:command:)` is async and waits for the model's first snapshot, so a
// view that takes the connection must show something until then, and say why when it fails. The
// Network and Console views' public initializers over a transport share this, so they wait and fail
// alike. Rejected: making the plugin transport itself start empty and connect later (every view
// drawing from one would need an empty snapshot, and `direct(to:)` would carry a state it never
// has), and a public type (a plugin's view is the public face; how it waits is not part of the
// plugin contract).

#if DEBUG
    /// Connects to a plugin's model over a ``DebugDrawerTransport`` and holds what came of it: the
    /// plugin transport a view draws from, once the model's first snapshot is in.
    @MainActor
    package final class DebugDrawerPluginConnection<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>: ObservableObject {
        /// How far connecting has got.
        package enum State {
            /// Waiting for the model's first snapshot.
            case connecting
            /// Connected: draw from the transport.
            case connected(DebugDrawerPluginTransport<Snapshot, Command>)
            /// Not reached, for this reason; a new connection may try again.
            case failed(DebugDrawerTransportError)
        }

        @Published package private(set) var state: State
        /// What to connect over.
        private let transport: any DebugDrawerTransport
        /// The ID the model is registered under.
        private let pluginID: String

        /// A connection to the model registered as `pluginID` at the other end of `transport`,
        /// made by ``connect()``.
        ///
        /// - Parameters:
        ///   - transport: The connection to the app's models.
        ///   - pluginID: The ID the model was registered under, usually its plugin's
        ///     ``DebugDrawerPlugin/id``.
        package init(transport: any DebugDrawerTransport, pluginID: String) {
            self.transport = transport
            self.pluginID = pluginID
            state = .connecting
        }

        /// Connects, unless connected or failed already, and returns once the model's first
        /// snapshot is in or the connection fails. Cancelling the task leaves it connecting, so a
        /// later call tries again.
        package func connect() async {
            guard case .connecting = state else { return }
            do throws(DebugDrawerTransportError) {
                let connected = try await transport.connect(toPlugin: pluginID, snapshot: Snapshot.self, command: Command.self)
                // Another call may have finished first, while this one waited.
                guard case .connecting = state else { return }
                state = .connected(connected)
            } catch {
                guard error != .cancelled, case .connecting = state else { return }
                state = .failed(error)
            }
        }
    }
#endif
