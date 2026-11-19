import Darwin
import Foundation
import os

// The app's end of the socket transport: it listens on a Unix domain socket, and serves each
// viewer that connects through a `RegistrySession` of its own, so each viewer gets the plugins it
// asked for. For a sidecar app the socket lives in the app group's container, which both apps can
// reach; a socket file left by an earlier run that nothing answers on is replaced, and one a live
// server answers on is not.

#if DEBUG
    /// Serves a ``DebugDrawerModelRegistry``'s models over a Unix domain socket, to each
    /// ``DebugDrawerSocketTransport`` that connects while it runs.
    ///
    /// ```swift
    /// let group = try DebugDrawerAppGroupContainer(groupIdentifier: "TEAMID.com.example.debug")
    /// let server = DebugDrawerSocketServer(registry: registry, socketPath: group.socketPath)
    /// try server.start()
    /// ```
    ///
    /// The path can be of any length, a group container's in the iOS simulator included; the
    /// socket's file name, its last component, holds at most 103 bytes. Release builds get a
    /// stand-in that serves nothing.
    @MainActor
    public final class DebugDrawerSocketServer {
        private static let logger = Logger(subsystem: "DebugDrawer", category: "DebugDrawerSocketServer")

        private let registry: DebugDrawerModelRegistry
        /// Where the socket is.
        public let socketPath: String
        private var listener: SocketListener?
        /// Each connected viewer, until it disconnects.
        private var viewers: [ObjectIdentifier: (connection: SocketConnection, session: RegistrySession)] = [:]

        /// A server of `registry`'s models at `socketPath`; it listens once started.
        ///
        /// - Parameters:
        ///   - registry: The models to serve.
        ///   - socketPath: Where to make the socket.
        public init(registry: DebugDrawerModelRegistry, socketPath: String) {
            self.registry = registry
            self.socketPath = socketPath
        }

        /// Whether the server is listening.
        public var isRunning: Bool {
            listener != nil
        }

        /// Makes the socket and listens on it. Does nothing while the server runs.
        ///
        /// The socket's directory is made if it doesn't exist.
        ///
        /// - Throws: ``DebugDrawerTransportError/socketPathTooLong`` when the socket's file name
        ///   doesn't fit a socket's address, ``DebugDrawerTransportError/accessDenied`` when the
        ///   system refuses access to the socket or its directory (the app group missing from the
        ///   app's entitlements, or the person declining macOS's prompt), and
        ///   ``DebugDrawerTransportError/cannotServe`` when something else is at the path or the
        ///   socket can't be made. Nothing is made then.
        public func start() throws(DebugDrawerTransportError) {
            guard listener == nil else { return }
            guard UnixSocketAddress.isReachable(socketPath) else { throw .socketPathTooLong }
            let directory = URL(filePath: socketPath, directoryHint: .notDirectory).deletingLastPathComponent()
            try DirectoryAccess.prepare(directory, need: .readWrite, otherwise: .cannotServe)
            try removeStaleSocket()
            let listener = try SocketListener(path: socketPath)
            self.listener = listener
            let accepted = listener.accepted
            // The loop runs until the listener's stream finishes, after `stop()`, so a connection
            // accepted just before is closed rather than left open with nothing serving it.
            Task { [weak self] in
                for await client in accepted {
                    guard let self, self.listener === listener else {
                        Darwin.close(client)
                        continue
                    }
                    serve(client)
                }
            }
        }

        /// Stops listening, disconnects every viewer and removes the socket. The server can start
        /// again.
        public func stop() {
            listener?.cancel()
            listener = nil
            for viewer in viewers.values {
                viewer.session.close()
                viewer.connection.close()
            }
            viewers = [:]
        }

        /// Serves the viewer connected on `descriptor` until it disconnects.
        private func serve(_ descriptor: Int32) {
            let connection = SocketConnection(descriptor: descriptor)
            let session = RegistrySession(registry: registry, link: .stream) {
                connection.send($0)
            } disconnect: {
                connection.closeAfterSending()
            }
            let key = ObjectIdentifier(connection)
            viewers[key] = (connection, session)
            Task { [weak self] in
                for await message in connection.messages {
                    session.receive(message)
                }
                session.close()
                self?.viewers[key] = nil
            }
        }

        /// Removes a socket file nothing answers on, left by a run that ended without stopping.
        private func removeStaleSocket() throws(DebugDrawerTransportError) {
            var status = stat()
            guard lstat(socketPath, &status) == 0 else {
                let code = errno
                guard code == ENOENT else { throw DirectoryAccess.failure(code, at: socketPath, otherwise: .cannotServe) }
                return
            }
            guard status.st_mode & S_IFMT == S_IFSOCK else { throw .cannotServe }
            if let live = UnixSocketAddress.connect(to: socketPath) {
                Darwin.close(live)
                throw .cannotServe
            }
            // A socket this process may not connect to isn't known to be stale: leave it.
            let code = errno
            guard !DirectoryAccess.isDenial(code) else { throw DirectoryAccess.failure(code, at: socketPath, otherwise: .cannotServe) }
            Self.logger.debug("Replaced a stale socket at \(self.socketPath, privacy: .private)")
            unlink(socketPath)
        }
    }
#else
    // The release stand-in: the same members, serving nothing.

    /// Release builds serve nothing: this stand-in never listens.
    @MainActor
    public final class DebugDrawerSocketServer {
        /// Where the socket would be.
        public let socketPath: String

        /// A server that never listens.
        ///
        /// - Parameters:
        ///   - registry: Ignored.
        ///   - socketPath: Kept, and never made.
        public init(registry: DebugDrawerModelRegistry, socketPath: String) {
            self.socketPath = socketPath
        }

        /// Always `false`.
        public var isRunning: Bool {
            false
        }

        /// Does nothing.
        public func start() throws(DebugDrawerTransportError) {}

        /// Does nothing.
        public func stop() {}
    }
#endif
