import Combine
import DebugDrawerReceiver
import Foundation
import os

// The app's side of every transport: which models it offers, by plugin ID. It holds each model
// type-erased behind `RegisteredModel`, so one registry holds models of different snapshot and
// command types, and each transport asks it for what it needs: the in-process one for the model
// itself, the socket and store servers for its snapshots as JSON and a way to perform a command
// decoded from JSON. Registration is explicit: a plugin's model is offered beyond the drawer only
// when the app says so. Rejected: plugins registering their models on install (an app would
// expose what it never chose to), and a registry keyed by model type (two plugins can share a
// model type; the plugin ID is what a viewer knows).
//
// It also remembers the IDs of the commands performed lately, across every server serving it, so a
// command a sidecar sent over the socket and sent again through the store, once the socket went
// before its acknowledgement arrived, is performed once. The newest `rememberedCommands` are kept:
// what a viewer sends again is what it sent last, unacknowledged. Rejected: remembering them in
// each session (the socket's and the store's are different sessions), and on disk (a command
// performed in a process since killed acted on models that went with it).
//
// Made with `DebugDrawerSessions`, the registry is the sidecar's gate: it serves the sessions
// under their own ID, and every command a transport carries in, over the socket or the store,
// goes through them, applied only within an open session and to a model registered with a
// `DebugDrawerChangeScope`. A refused command is still acknowledged and its ID remembered, as a
// refusal is final. The in-process transport hands out the model itself, so the app's own drawer
// is never gated: it is the app's code, not a sidecar's.

#if DEBUG
    /// The plugin models an app offers to viewers outside its drawer, each under its plugin's ID.
    ///
    /// Register a model, then serve the registry over the transports a viewer may connect
    /// through: ``DebugDrawerInProcessTransport`` reads it directly, a ``DebugDrawerSocketServer``
    /// and a ``DebugDrawerAppGroupStoreServer`` carry it out of the process. Several can serve one
    /// registry at once.
    ///
    /// ```swift
    /// let registry = DebugDrawerModelRegistry()
    /// registry.register(LaunchTimeModel.shared, id: "DebugDrawerLaunchTimePlugin.LaunchTimePlugin")
    /// let server = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
    /// try server.start()
    /// ```
    ///
    /// Release builds get a stand-in that offers nothing.
    @MainActor
    public final class DebugDrawerModelRegistry {
        private static let logger = Logger(subsystem: "DebugDrawer", category: "DebugDrawerModelRegistry")

        /// The models, by plugin ID.
        private(set) var models: [String: RegisteredModel] = [:]
        /// What to tell when a model is registered or unregistered, by the token that removes it.
        private var observers: [UUID: @MainActor (String) -> Void] = [:]
        /// The IDs of the commands performed lately, and the order they came in, oldest first.
        private var performedCommands: Set<UUID> = []
        private var performedOrder: [UUID] = []
        /// How many command IDs are remembered.
        static let rememberedCommands = 4096
        /// The sessions every command from outside the process acts within; `nil` when commands
        /// aren't gated.
        private let sessions: DebugDrawerSessions?

        /// An empty registry, performing every command a viewer sends.
        public init() {
            sessions = nil
        }

        /// A registry whose commands from outside the process act only within `sessions`: it
        /// serves them under ``DebugDrawerSessions/pluginID``, so a sidecar can open one, and
        /// refuses a command while none is open, or to a model registered without a
        /// ``DebugDrawerChangeScope``.
        ///
        /// - Parameter sessions: The sessions to act within.
        public init(sessions: DebugDrawerSessions) {
            self.sessions = sessions
            models[DebugDrawerSessions.pluginID] = RegisteredModel(sessions, scope: nil)
        }

        /// Offers `model` under `id`, in place of any model registered under it before.
        ///
        /// In a registry made with ``DebugDrawerSessions``, a viewer reads the model's snapshots
        /// and its commands are refused: register it with ``register(_:id:scope:)`` to let a
        /// session's commands change it.
        ///
        /// - Parameters:
        ///   - model: The model to offer.
        ///   - id: The ID a viewer connects to it by, usually its plugin's ``DebugDrawerPlugin/id``.
        public func register<Model: DebugDrawerPluginModel>(_ model: Model, id: String) {
            models[id] = RegisteredModel(model, scope: nil)
            notify(id)
        }

        /// Offers `model` under `id` as a capability whose commands a session applies, in place
        /// of any model registered under it before.
        ///
        /// - Parameters:
        ///   - model: The model to offer.
        ///   - id: The ID a viewer connects to it by, and the audit log names it by.
        ///   - scope: What becomes of its changes as the session that made them ends: reverted
        ///     with a command, or kept.
        public func register<Model: DebugDrawerPluginModel>(_ model: Model, id: String, scope: DebugDrawerChangeScope<Model>) {
            models[id] = RegisteredModel(model, scope: DebugDrawerSessions.CapabilityScope(scope, of: model))
            notify(id)
        }

        /// Performs the command `payload` encodes on the model registered under `id`, as a
        /// transport carried it in: within the sessions, when the registry has them.
        func perform(_ payload: Data, for id: String) {
            guard let model = models[id] else {
                Self.logger.notice("Dropped a command for \(id, privacy: .public): no model is registered")
                sessions?.refuse(id, .unknownCapability)
                return
            }
            // The sessions' own commands open and end a session, so no session gates them; the
            // sessions record what comes of them.
            guard let sessions, id != DebugDrawerSessions.pluginID else {
                if !model.perform(payload) {
                    Self.logger.error("Dropped a command for \(id, privacy: .public) that didn't decode")
                }
                return
            }
            sessions.apply(to: id, scope: model.scope) { model.perform(payload) }
        }

        /// Stops offering the model registered under `id`. A viewer connected to it stops getting
        /// snapshots, and its commands are dropped; nothing happens when no model is registered
        /// under `id`.
        ///
        /// - Parameter id: The ID the model was registered under.
        public func unregister(id: String) {
            guard models.removeValue(forKey: id) != nil else { return }
            notify(id)
        }

        /// Calls `handler` with a plugin ID each time a model is registered or unregistered under
        /// it, until ``removeObserver(_:)`` gets the token returned.
        func observe(_ handler: @escaping @MainActor (String) -> Void) -> UUID {
            let token = UUID()
            observers[token] = handler
            return token
        }

        func removeObserver(_ token: UUID) {
            observers[token] = nil
        }

        /// Whether the command `id` names arrives for the first time, which it then no longer
        /// does: `false` when it was performed, by any server of this registry, among the last
        /// ``rememberedCommands``.
        func isFirstDelivery(of id: UUID) -> Bool {
            guard performedCommands.insert(id).inserted else { return false }
            performedOrder.append(id)
            if performedOrder.count > Self.rememberedCommands {
                performedCommands.remove(performedOrder.removeFirst())
            }
            return true
        }

        private func notify(_ id: String) {
            for handler in observers.values {
                handler(id)
            }
        }
    }

    /// A registered model, its snapshot and command types erased, so one registry holds models of
    /// every type.
    @MainActor
    struct RegisteredModel {
        /// The model, for the in-process transport.
        private let model: any DebugDrawerPluginModel
        /// The model's current snapshot, then the snapshot after each change, as JSON: each one
        /// different from the one before.
        let encodedSnapshots: @MainActor () -> AsyncStream<Data>
        /// Performs the command `payload` encodes; `false` when it isn't one of the model's
        /// commands.
        let perform: @MainActor (_ payload: Data) -> Bool
        /// What becomes of its changes as a session ends; `nil` when the host didn't say.
        let scope: DebugDrawerSessions.CapabilityScope?

        init<Model: DebugDrawerPluginModel>(_ model: Model, scope: DebugDrawerSessions.CapabilityScope?) {
            self.model = model
            self.scope = scope
            encodedSnapshots = { model.encodedSnapshots() }
            perform = { payload in
                guard let command = try? JSONDecoder().decode(Model.Command.self, from: payload) else { return false }
                model.perform(command)
                return true
            }
        }

        /// A direct transport to the model, or `nil` when its types aren't `Snapshot` and
        /// `Command`.
        func directTransport<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>(
            snapshot: Snapshot.Type,
            command: Command.Type
        ) -> DebugDrawerPluginTransport<Snapshot, Command>? {
            func open<Model: DebugDrawerPluginModel>(_ model: Model) -> DebugDrawerPluginTransport<Snapshot, Command>? {
                guard Model.Snapshot.self == Snapshot.self, Model.Command.self == Command.self else { return nil }
                return DebugDrawerPluginTransport<Model.Snapshot, Model.Command>.direct(to: model) as? DebugDrawerPluginTransport<Snapshot, Command>
            }
            return open(model)
        }
    }

    extension DebugDrawerPluginModel {
        /// The model's snapshots as JSON, through a direct transport's `snapshots()`, which folds
        /// changes made while the reader is busy; a snapshot that encodes to the bytes of the one
        /// before is skipped, so an announced change that changed nothing sends nothing.
        fileprivate func encodedSnapshots() -> AsyncStream<Data> {
            let transport = DebugDrawerPluginTransport.direct(to: self)
            return AsyncStream { continuation in
                let forwarding = Task { @MainActor in
                    var previous: Data?
                    for await snapshot in transport.snapshots() {
                        guard let encoded = try? TransportMessage.payload(snapshot), encoded != previous else { continue }
                        previous = encoded
                        continuation.yield(encoded)
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in forwarding.cancel() }
            }
        }
    }
#else
    // The release stand-in: the same members, offering nothing.

    /// Release builds offer no models: this stand-in keeps none.
    @MainActor
    public final class DebugDrawerModelRegistry {
        /// An empty registry.
        public init() {}

        /// An empty registry.
        ///
        /// - Parameter sessions: Ignored.
        public init(sessions: DebugDrawerSessions) {}

        /// Does nothing.
        ///
        /// - Parameters:
        ///   - model: Ignored.
        ///   - id: Ignored.
        public func register<Model: DebugDrawerPluginModel>(_ model: Model, id: String) {}

        /// Does nothing.
        ///
        /// - Parameters:
        ///   - model: Ignored.
        ///   - id: Ignored.
        ///   - scope: Ignored.
        public func register<Model: DebugDrawerPluginModel>(_ model: Model, id: String, scope: DebugDrawerChangeScope<Model>) {}

        /// Does nothing.
        ///
        /// - Parameter id: Ignored.
        public func unregister(id: String) {}
    }
#endif
