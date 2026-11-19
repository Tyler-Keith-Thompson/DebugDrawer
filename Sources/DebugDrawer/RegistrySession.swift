import Foundation
import os

// The models' half of every transport that leaves the process, written once: a socket server runs
// one per connected viewer, the store server one for the directory, and `DebugDrawerRemote`'s
// network server one per paired viewer (`package`, so that module reuses it). It forwards each
// plugin's snapshots as messages and performs the commands that come back, through the registry,
// so a model registered after a viewer asked for it is forwarded from then on, and one registered
// anew is forwarded afresh. On a stream it says hello first, and closes a viewer it shares no
// protocol version with (`TransportPeer`). A command with an ID is performed only the first time
// the registry sees that ID, then acknowledged on a stream to a viewer that has the capability,
// once performed, so an acknowledgement means the command landed. The store needs none: removing
// its file is what takes the command.

#if DEBUG
    /// Serves a ``DebugDrawerModelRegistry``'s models to one viewer, or one store, as messages.
    @MainActor
    package final class RegistrySession {
        private static let logger = Logger(subsystem: "DebugDrawer", category: "RegistrySession")

        private let registry: DebugDrawerModelRegistry
        private let link: TransportLink
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
            self.link = link
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
                // Acknowledged once done with, performed, refused (outside a session, say) or
                // dropped, so the viewer never sends it again: a refusal is final, and a sidecar
                // that opens a session sends the command anew, under a new ID.
                defer {
                    if let id = message.commandID { acknowledge(id, of: message.pluginID) }
                }
                if let id = message.commandID, !registry.isFirstDelivery(of: id) {
                    Self.logger.debug("Skipped a command for \(message.pluginID, privacy: .public) already performed")
                    return
                }
                registry.perform(message.payload, for: message.pluginID)
            case .snapshot, .hello, .acknowledgement, .unknown:
                Self.logger.debug("Ignored a \(message.kind.name, privacy: .public) sent to the models' side")
            }
        }

        /// Tells the viewer the command `id` names is done with, on a stream to a viewer that
        /// listens for it.
        private func acknowledge(_ id: UUID, of pluginID: String) {
            guard link == .stream, peer.uses(.acknowledgements) else { return }
            send(TransportMessage(kind: .acknowledgement, pluginID: pluginID, commandID: id))
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
