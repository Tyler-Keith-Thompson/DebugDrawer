#if DEBUG && canImport(DebugDrawerRemote)
    import DebugDrawer
    import Foundation

    // One plugin of the app's, as the relay serves it to a Mac viewer: a model whose snapshot is
    // the app's latest, read through the sidecar's transport, and whose commands go back through
    // it. The relay registers it only once the app's first snapshot is in, so a viewer never reads
    // a placeholder, and drops it as the session ends, so it keeps nothing past the session. It
    // gates nothing itself: the receiver performs or refuses each command as it would the
    // sidecar's own, within the session and its grant.

    /// The app's model of one plugin, read and driven through the sidecar's transport.
    @MainActor
    final class RelayedModel: DebugDrawerPluginModel {
        @Published private(set) var snapshot: JSONValue
        private var transport: DebugDrawerPluginTransport<JSONValue, JSONValue>?
        private var reading: Task<Void, Never>?

        /// A model over `transport`, starting from its current snapshot.
        init(transport: DebugDrawerPluginTransport<JSONValue, JSONValue>) {
            self.transport = transport
            snapshot = transport.snapshot
            reading = Task { [weak self] in
                for await snapshot in transport.snapshots() {
                    guard let self else { return }
                    guard snapshot != self.snapshot else { continue }
                    self.snapshot = snapshot
                }
            }
        }

        isolated deinit {
            reading?.cancel()
        }

        func perform(_ command: JSONValue) {
            transport?.send(command)
        }

        /// Stops reading and lets go of the transport: later commands go nowhere.
        func finish() {
            reading?.cancel()
            reading = nil
            transport = nil
        }
    }
#endif
