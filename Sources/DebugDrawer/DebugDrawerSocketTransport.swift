import Foundation

// The viewer's end of the socket transport: one connection to a `DebugDrawerSocketServer`, read on
// its own queue and handed to `RemoteModels` on the main actor in order. It asks for a plugin's
// snapshots when a view first connects to it, so the app encodes only what some viewer shows.

#if DEBUG
    /// A ``DebugDrawerTransport`` to an app's models over a Unix domain socket, live while the app
    /// runs its ``DebugDrawerSocketServer``.
    ///
    /// Commands reach the app as soon as it reads them, and each snapshot it publishes arrives as
    /// it changes. When the app quits or stops the server, the transports this handed out keep
    /// their last snapshot, commands sent to them are dropped, and ``isConnected`` turns `false`.
    /// A sidecar that should go on through the store then, and come back, holds a
    /// ``DebugDrawerSidecarTransport``, which does both without losing a command. The transports
    /// it hands out hold it open; it disconnects on ``close()``, or once neither it nor any of
    /// them is held.
    ///
    /// Release builds get a stand-in whose initializer throws
    /// ``DebugDrawerTransportError/unreachable``.
    @MainActor
    public final class DebugDrawerSocketTransport: DebugDrawerTransport, ObservableObject {
        private let connection: SocketConnection
        private let models: RemoteModels
        /// Whether the connection is still open; `false` once the app, or ``close()``, ends it.
        @Published public private(set) var isConnected = true

        /// Connects to the server listening at `socketPath`.
        ///
        /// - Parameter socketPath: The server's ``DebugDrawerSocketServer/socketPath``.
        /// - Throws: ``DebugDrawerTransportError/socketPathTooLong`` when the socket's file name
        ///   doesn't fit a socket's address, and ``DebugDrawerTransportError/unreachable`` when nothing listens
        ///   there.
        public init(socketPath: String) throws(DebugDrawerTransportError) {
            guard UnixSocketAddress.isReachable(socketPath) else { throw .socketPathTooLong }
            guard let descriptor = UnixSocketAddress.connect(to: socketPath) else { throw .unreachable }
            let connection = SocketConnection(descriptor: descriptor)
            let models = RemoteModels(link: .stream) {
                connection.send($0)
            } disconnect: {
                connection.close()
            }
            self.connection = connection
            self.models = models
            Task { [weak self] in
                for await message in connection.messages {
                    models.receive(message)
                }
                models.close()
                self?.isConnected = false
            }
        }

        deinit {
            connection.close()
        }

        /// The plugin's model in the app, once its first snapshot arrives over the socket.
        ///
        /// - Parameters:
        ///   - pluginID: The ID the model was registered under.
        ///   - snapshot: The model's `Snapshot` type.
        ///   - command: The model's `Command` type.
        /// - Returns: A transport showing the model's snapshots as they arrive and sending its
        ///   commands to the app.
        /// - Throws: ``DebugDrawerTransportError/mismatchedTypes``,
        ///   ``DebugDrawerTransportError/disconnected``, ``DebugDrawerTransportError/cancelled``, or
        ///   ``DebugDrawerTransportError/incompatibleVersion`` when the app's protocol version is
        ///   two or more major versions from this build's.
        public func connect<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>(
            toPlugin pluginID: String,
            snapshot: Snapshot.Type,
            command: Command.Type
        ) async throws(DebugDrawerTransportError) -> DebugDrawerPluginTransport<Snapshot, Command> {
            try await models.connect(toPlugin: pluginID, snapshot: snapshot, command: command, holding: self)
        }

        /// Disconnects from the app. The transports this handed out keep their last snapshot.
        public func close() {
            connection.close()
        }

        /// Waits for the app's hello: `true` once it said one this build agrees with, `false` when
        /// the connection closes first.
        func handshake() async -> Bool {
            await models.handshake()
        }

        /// Sends `message`, a command with an ID: `false`, and nothing sent, once the connection
        /// is closed.
        func send(command message: TransportMessage) -> Bool {
            models.send(command: message)
        }

        /// The commands sent to an app that acknowledges them, and not acknowledged, oldest first.
        var unacknowledgedCommands: [TransportMessage] {
            models.unacknowledgedCommands
        }
    }
#else
    // The release stand-in: the same members, never connecting.

    /// Release builds connect to nothing: this stand-in's initializer throws
    /// ``DebugDrawerTransportError/unreachable``.
    @MainActor
    public final class DebugDrawerSocketTransport: DebugDrawerTransport, ObservableObject {
        /// Always `false`.
        @Published public private(set) var isConnected = false

        /// Throws ``DebugDrawerTransportError/unreachable``.
        ///
        /// - Parameter socketPath: Ignored.
        /// - Throws: ``DebugDrawerTransportError/unreachable``, always.
        public init(socketPath: String) throws(DebugDrawerTransportError) {
            throw .unreachable
        }

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

        /// Does nothing.
        public func close() {}
    }
#endif
