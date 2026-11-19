import Foundation
import os

// The models' half of every transport that leaves the process, written once: a socket server runs
// one per connected viewer, the store server one for the directory, and `DebugDrawerRemote`'s
// network server one per paired viewer (`package`, so that module reuses it). It forwards each
// plugin's snapshots as messages and performs the commands that come back, through the registry,
// so a model registered after a viewer asked for it is forwarded from then on, and one registered
// anew is forwarded afresh. On a stream it says hello first, and closes a viewer it shares no
// protocol version with (`TransportPeer`).

#if DEBUG
    /// Serves a ``DebugDrawerModelRegistry``'s models to one viewer, or one store, as messages.
    @MainActor
    package final class RegistrySession {
        private static let logger = Logger(subsystem: "DebugDrawer", category: "RegistrySession")

        private let registry: DebugDrawerModelRegistry
        private let send: @MainActor (TransportMessage) -> Void
        private let disconnect: @MainActor () -> Void
        /// Forwards each wanted plugin's snapshots while its model is registered.
        private var forwarding: [String: Task<Void, Never>] = [:]
        /// The plugins the viewer asked for; `nil` once it wants every plugin.
        private var wanted: Set<String>? = []
        private var registryObservation: UUID?
        /// The viewer, as its messages describe it.
        package private(set) var peer = TransportPeer()
        private var isClosed = false

        /// A session serving `registry` over `link`; on a stream it says hello at once.
        ///
        /// - Parameters:
        ///   - registry: The models to serve.
        ///   - link: What carries the messages.
        ///   - send: Sends a message to the viewer.
        ///   - disconnect: Ends the connection, after the messages sent before it: called when the
        ///     viewer shares no protocol version with this build.
        package init(
            registry: DebugDrawerModelRegistry,
            link: TransportLink,
            send: @escaping @MainActor (TransportMessage) -> Void,
            disconnect: @escaping @MainActor () -> Void = {}
        ) {
            self.registry = registry
            self.send = send
            self.disconnect = disconnect
            registryObservation = registry.observe { [weak self] id in self?.registrationChanged(id) }
            if link == .stream {
                send(.hello(.current))
            }
        }

        /// Forwards every plugin's snapshots, those registered now and later: what a store
        /// keeps.
        func forwardEveryPlugin() {
            wanted = nil
            for id in registry.models.keys.sorted() where forwarding[id] == nil {
                forward(id)
            }
        }

        /// Takes in a message from the viewer: keeps a hello, forwards the plugin a subscribe
        /// names and stops one an unsubscribe names, performs the command a command carries, and
        /// drops a kind this build doesn't know.
        package func receive(_ message: TransportMessage) {
            guard !isClosed else { return }
            switch peer.admit(message) {
            case .agreed, .ignored:
                return
            case .incompatible:
                close()
                disconnect()
            case let .deliver(message):
                act(on: message)
            }
        }

        /// Stops forwarding, for good.
        package func close() {
            isClosed = true
            if let registryObservation { registry.removeObserver(registryObservation) }
            registryObservation = nil
            for task in forwarding.values {
                task.cancel()
            }
            forwarding = [:]
        }

        private func act(on message: TransportMessage) {
            switch message.kind {
            case .subscribe:
                guard wanted?.insert(message.pluginID).inserted == true else { return }
                forward(message.pluginID)
            case .unsubscribe:
                guard wanted?.remove(message.pluginID) != nil else { return }
                forwarding.removeValue(forKey: message.pluginID)?.cancel()
            case .command:
                guard let model = registry.models[message.pluginID] else {
                    Self.logger.notice("Dropped a command for \(message.pluginID, privacy: .public): no model is registered")
                    return
                }
                if !model.perform(message.payload) {
                    Self.logger.error("Dropped a command for \(message.pluginID, privacy: .public) that didn't decode")
                }
            case .snapshot, .hello, .unknown:
                Self.logger.debug("Ignored a \(message.kind.name, privacy: .public) sent to the models' side")
            }
        }

        private func registrationChanged(_ id: String) {
            guard wanted?.contains(id) ?? true else { return }
            forward(id)
        }

        /// Forwards the plugin's snapshots from its model registered now, the current one first,
        /// in place of any model forwarded before; nothing while none is registered.
        private func forward(_ id: String) {
            forwarding[id]?.cancel()
            forwarding[id] = nil
            guard let model = registry.models[id] else { return }
            let snapshots = model.encodedSnapshots()
            forwarding[id] = Task { @MainActor [weak self] in
                for await payload in snapshots {
                    self?.send(TransportMessage(kind: .snapshot, pluginID: id, payload: payload))
                }
            }
        }
    }
#endif
