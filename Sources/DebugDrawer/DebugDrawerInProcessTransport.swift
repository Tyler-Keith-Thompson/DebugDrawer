// The transport inside the app's own process: what the drawer does, through the registry. It hands
// out `direct(to:)` transports, so a command lands before `send` returns and nothing is encoded,
// exactly as a plugin's body joining its view to its model does.

#if DEBUG
    /// A ``DebugDrawerTransport`` to the models a ``DebugDrawerModelRegistry`` holds in this
    /// process: each transport it hands out is the model's
    /// ``DebugDrawerPluginTransport/direct(to:)``, so a command lands before `send` returns.
    ///
    /// Release builds get a stand-in that throws ``DebugDrawerTransportError/unreachable``.
    @MainActor
    public final class DebugDrawerInProcessTransport: DebugDrawerTransport {
        private let registry: DebugDrawerModelRegistry

        /// A transport to the models `registry` holds.
        ///
        /// - Parameter registry: The app's models.
        public init(registry: DebugDrawerModelRegistry) {
            self.registry = registry
        }

        /// The model registered as `pluginID`, joined directly; waits for it to be registered.
        ///
        /// - Parameters:
        ///   - pluginID: The ID the model was registered under.
        ///   - snapshot: The model's `Snapshot` type.
        ///   - command: The model's `Command` type.
        /// - Returns: The model's direct transport.
        /// - Throws: ``DebugDrawerTransportError/mismatchedTypes`` when the model registered has
        ///   other types, and ``DebugDrawerTransportError/cancelled`` when the waiting task is
        ///   cancelled.
        public func connect<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>(
            toPlugin pluginID: String,
            snapshot: Snapshot.Type,
            command: Command.Type
        ) async throws(DebugDrawerTransportError) -> DebugDrawerPluginTransport<Snapshot, Command> {
            let (registrations, registered) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let token = registry.observe { id in
                if id == pluginID { registered.yield() }
            }
            defer { registry.removeObserver(token) }
            registered.yield()
            for await _ in registrations {
                guard let model = registry.models[pluginID] else { continue }
                guard let transport = model.directTransport(snapshot: snapshot, command: command) else {
                    throw .mismatchedTypes
                }
                return transport
            }
            throw .cancelled
        }
    }
#else
    // The release stand-in: the same members, connecting to nothing.

    /// Release builds offer no models: this stand-in throws
    /// ``DebugDrawerTransportError/unreachable``.
    @MainActor
    public final class DebugDrawerInProcessTransport: DebugDrawerTransport {
        /// A transport that connects to nothing.
        ///
        /// - Parameter registry: Ignored.
        public init(registry: DebugDrawerModelRegistry) {}

        /// Throws ``DebugDrawerTransportError/unreachable``.
        ///
        /// - Parameters:
        ///   - pluginID: Ignored.
        ///   - snapshot: Ignored.
        ///   - command: Ignored.
        /// - Returns: Never.
        /// - Throws: ``DebugDrawerTransportError/unreachable``, always.
        public func connect<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>(
            toPlugin pluginID: String,
            snapshot: Snapshot.Type,
            command: Command.Type
        ) async throws(DebugDrawerTransportError) -> DebugDrawerPluginTransport<Snapshot, Command> {
            throw .unreachable
        }
    }
#endif
