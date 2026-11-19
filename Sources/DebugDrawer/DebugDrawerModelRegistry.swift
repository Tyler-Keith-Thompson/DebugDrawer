import Combine
import Foundation

// The app's side of every transport: which models it offers, by plugin ID. It holds each model
// type-erased behind `RegisteredModel`, so one registry holds models of different snapshot and
// command types, and each transport asks it for what it needs: the in-process one for the model
// itself, the socket and store servers for its snapshots as JSON and a way to perform a command
// decoded from JSON. Registration is explicit: a plugin's model is offered beyond the drawer only
// when the app says so. Rejected: plugins registering their models on install (an app would
// expose what it never chose to), and a registry keyed by model type (two plugins can share a
// model type; the plugin ID is what a viewer knows).

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
        /// The models, by plugin ID.
        private(set) var models: [String: RegisteredModel] = [:]
        /// What to tell when a model is registered or unregistered, by the token that removes it.
        private var observers: [UUID: @MainActor (String) -> Void] = [:]

        /// An empty registry.
        public init() {}

        /// Offers `model` under `id`, in place of any model registered under it before.
        ///
        /// - Parameters:
        ///   - model: The model to offer.
        ///   - id: The ID a viewer connects to it by, usually its plugin's ``DebugDrawerPlugin/id``.
        public func register<Model: DebugDrawerPluginModel>(_ model: Model, id: String) {
            models[id] = RegisteredModel(model)
            notify(id)
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

        init<Model: DebugDrawerPluginModel>(_ model: Model) {
            self.model = model
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

        /// Does nothing.
        ///
        /// - Parameters:
        ///   - model: Ignored.
        ///   - id: Ignored.
        public func register<Model: DebugDrawerPluginModel>(_ model: Model, id: String) {}

        /// Does nothing.
        ///
        /// - Parameter id: Ignored.
        public func unregister(id: String) {}
    }
#endif
