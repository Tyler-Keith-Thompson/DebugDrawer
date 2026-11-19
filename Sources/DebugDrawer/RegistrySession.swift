import Foundation
import os

// The models' half of every transport that leaves the process, written once: a socket server runs
// one per connected viewer, the store server one for the directory, and DD-19's network transport
// one per remote viewer. It forwards each plugin's snapshots as messages and performs the commands
// that come back, through the registry, so a model registered after a viewer asked for it is
// forwarded from then on, and one registered anew is forwarded afresh.

#if DEBUG
    /// Serves a ``DebugDrawerModelRegistry``'s models to one viewer, or one store, as messages.
    @MainActor
    final class RegistrySession {
        private static let logger = Logger(subsystem: "DebugDrawer", category: "RegistrySession")

        private let registry: DebugDrawerModelRegistry
        private let send: @MainActor (TransportMessage) -> Void
        /// Forwards each wanted plugin's snapshots while its model is registered.
        private var forwarding: [String: Task<Void, Never>] = [:]
        /// The plugins the viewer asked for; `nil` once it wants every plugin.
        private var wanted: Set<String>? = []
        private var registryObservation: UUID?

        init(registry: DebugDrawerModelRegistry, send: @escaping @MainActor (TransportMessage) -> Void) {
            self.registry = registry
            self.send = send
            registryObservation = registry.observe { [weak self] id in self?.registrationChanged(id) }
        }

        /// Forwards every plugin's snapshots, those registered now and later: what a store
        /// keeps.
        func forwardEveryPlugin() {
            wanted = nil
            for id in registry.models.keys.sorted() where forwarding[id] == nil {
                forward(id)
            }
        }

        /// Takes in a message from the viewer: forwards the plugin a subscribe names, performs the
        /// command a command carries.
        func receive(_ message: TransportMessage) {
            switch message.kind {
            case .subscribe:
                guard wanted?.insert(message.pluginID).inserted == true else { return }
                forward(message.pluginID)
            case .command:
                guard let model = registry.models[message.pluginID] else {
                    Self.logger.notice("Dropped a command for \(message.pluginID, privacy: .public): no model is registered")
                    return
                }
                if !model.perform(message.payload) {
                    Self.logger.error("Dropped a command for \(message.pluginID, privacy: .public) that didn't decode")
                }
            case .snapshot:
                Self.logger.debug("Ignored a snapshot sent to the models' side")
            }
        }

        /// Stops forwarding, for good.
        func close() {
            if let registryObservation { registry.removeObserver(registryObservation) }
            registryObservation = nil
            for task in forwarding.values {
                task.cancel()
            }
            forwarding = [:]
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
