import Combine
import Foundation
import os

// A sidecar's one connection to the app, over whichever way reaches it: the socket while the app
// answers on it, the app-group store when it doesn't. It holds a store transport for its whole life
// and adopts a socket transport once the app's hello arrives over it, so the plugin transports it
// hands out keep drawing, and their commands keep landing, as the app goes to the background,
// quits, or comes back. Each plugin transport is a relay: its snapshots come from a transport of
// the channel in use, connected afresh at each switch.
//
// Commands are performed once, whichever way they go. Each carries an ID. Over the socket, one is
// kept until the app acknowledges it; when the socket goes, those not acknowledged are left in
// the store, oldest first, and the app's registry performs an ID it has already performed no
// more (an acknowledgement lost with the socket). Over the store, the files this left are kept;
// when the socket comes back, each file this can still remove (the app hadn't taken it) is sent
// over the socket before any newer command, so the order holds across both switches. An app
// without the `acknowledgements` capability keeps no commands to send again: what was in flight
// when its socket went may be lost, as before.
//
// Everything is event-driven. The socket going ends its stream, which `isConnected` reports; the
// socket coming back makes its file in its directory, which a dispatch source on that directory
// reports. A socket is adopted only after the app's hello, so the capabilities are known before
// any command goes over it; an app that says none (version 1) is read through the store. The store
// is read only while it is the channel in use, so the app's snapshots aren't read twice.
//
// Rejected: retrying the socket on a timer (a clock where the directory already says when the
// socket is made); sending every command both ways and letting the app drop the second (each
// would be read twice, and the store would fill while the socket works); keeping commands until a
// snapshot shows them (a command need not change a snapshot); and leaving the switch to each
// viewer, holding a socket transport and a store transport itself (each would redo it, and the
// commands in flight when the socket went would be lost).

#if DEBUG
    /// A ``DebugDrawerTransport`` for a sidecar app: over the app's socket while the app answers
    /// on it, and its app-group store when it doesn't, switching back and forth on its own.
    ///
    /// ```swift
    /// let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.example.debug")!
    /// let sidecar = try DebugDrawerSidecarTransport(
    ///     socketPath: container.appending(path: "drawer.sock").path,
    ///     storeDirectory: container.appending(path: "DebugDrawer")
    /// )
    /// ```
    ///
    /// The plugin transports it hands out show each snapshot the app publishes while the socket is
    /// up, and the last ones the app wrote to the store while it isn't. Their commands go over the
    /// socket, or wait in the store for the app; each is performed once, in the order sent, across
    /// both switches, when the app lists the `acknowledgements` capability. The transports it
    /// hands out hold it open; it stops on ``close()``, or once neither it nor any of them is held.
    ///
    /// Release builds get a stand-in whose initializer throws
    /// ``DebugDrawerTransportError/unreachable``.
    @MainActor
    public final class DebugDrawerSidecarTransport: DebugDrawerTransport, ObservableObject {
        private static let logger = Logger(subsystem: "DebugDrawer", category: "DebugDrawerSidecarTransport")

        /// How the transport reaches the app now: ``Channel/store`` until the app's hello arrives
        /// over the socket.
        @Published public private(set) var channel = Channel.store

        private let socketPath: String
        private let store: DebugDrawerAppGroupStoreTransport
        /// Says when an entry of the socket's directory changes: the socket made, or removed.
        private let socketDirectory: DirectoryWatcher
        /// The socket in use; `nil` while on the store.
        private var socket: DebugDrawerSocketTransport?
        private var socketDisconnection: AnyCancellable?
        /// A socket connected and waiting for the app's hello.
        private var reaching: Task<Void, Never>?
        /// Whether the socket's directory changed while a socket was being reached, so one more
        /// try is due if that one fails.
        private var socketChangedWhileReaching = false
        /// Each plugin transport handed out and still held, by a token of its own.
        private var relays: [UUID: any SidecarRelay] = [:]
        /// The commands left in the store, oldest first, with their files.
        private var leftInStore: [(file: URL, message: TransportMessage)] = []
        private var isClosed = false

        /// Reads the app's store in `storeDirectory`, and reaches for its socket at `socketPath`
        /// at once and each time a socket is made there.
        ///
        /// - Parameters:
        ///   - socketPath: The app's ``DebugDrawerSocketServer/socketPath``, of any length; its
        ///     directory is made if it doesn't exist.
        ///   - storeDirectory: The app's ``DebugDrawerAppGroupStoreServer/directory``.
        /// - Throws: ``DebugDrawerTransportError/socketPathTooLong`` when the socket's file name
        ///   doesn't fit a socket's address, and ``DebugDrawerTransportError/unreachable`` when
        ///   either directory can't be made or watched.
        public init(socketPath: String, storeDirectory: URL) throws(DebugDrawerTransportError) {
            guard UnixSocketAddress.isReachable(socketPath) else { throw .socketPathTooLong }
            let directory = URL(filePath: socketPath, directoryHint: .notDirectory).deletingLastPathComponent()
            // The app may not have started yet; its server makes the socket here when it does.
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard let watcher = DirectoryWatcher(directory: directory) else { throw .unreachable }
            store = try DebugDrawerAppGroupStoreTransport(directory: storeDirectory)
            socketDirectory = watcher
            self.socketPath = socketPath
            Task { [weak self] in
                for await _ in watcher.changes where self?.socket == nil {
                    self?.reachForSocket()
                }
            }
            reachForSocket()
        }

        deinit {
            socketDirectory.cancel()
        }

        /// The plugin's model in the app, once its first snapshot arrives over the channel in use.
        ///
        /// - Parameters:
        ///   - pluginID: The ID the model was registered under.
        ///   - snapshot: The model's `Snapshot` type.
        ///   - command: The model's `Command` type.
        /// - Returns: A transport showing the model's snapshots over whichever channel is in use,
        ///   and carrying its commands the same way.
        /// - Throws: ``DebugDrawerTransportError/mismatchedTypes``,
        ///   ``DebugDrawerTransportError/disconnected`` once ``close()`` is called, or
        ///   ``DebugDrawerTransportError/cancelled``.
        public func connect<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>(
            toPlugin pluginID: String,
            snapshot: Snapshot.Type,
            command: Command.Type
        ) async throws(DebugDrawerTransportError) -> DebugDrawerPluginTransport<Snapshot, Command> {
            guard !isClosed else { throw .disconnected }
            let (snapshots, delivered) = AsyncStream<Snapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let (first, firstOutcome) = AsyncStream<Result<Snapshot, DebugDrawerTransportError>>.makeStream(bufferingPolicy: .bufferingNewest(1))
            let relay = SidecarPluginRelay<Snapshot, Command>(pluginID: pluginID, delivered: delivered, firstOutcome: firstOutcome)
            let token = UUID()
            relays[token] = relay
            relay.attach(to: socket ?? store)
            var outcome: Result<Snapshot, DebugDrawerTransportError>?
            for await result in first {
                outcome = result
                break
            }
            guard case let .success(initial) = outcome else {
                relays[token] = nil
                relay.finish()
                if case let .failure(error) = outcome { throw error }
                throw Task.isCancelled ? .cancelled : .disconnected
            }
            delivered.onTermination = { [weak self] _ in
                Task { @MainActor in self?.release(token) }
            }
            return DebugDrawerPluginTransport(initial: initial, snapshots: snapshots) { [self] command in
                guard let payload = try? TransportMessage.payload(command) else { return }
                send(TransportMessage(kind: .command, pluginID: pluginID, payload: payload, commandID: UUID()))
            }
        }

        /// Disconnects from the app: the transports this handed out keep their last snapshot, and
        /// drop later commands.
        public func close() {
            guard !isClosed else { return }
            isClosed = true
            socketDirectory.cancel()
            reaching?.cancel()
            socketDisconnection = nil
            socket?.close()
            socket = nil
            store.isReading = false
            for relay in relays.values {
                relay.finish()
            }
            relays = [:]
        }

        /// Connects to the socket, if something listens there, and adopts it once the app's hello
        /// arrives.
        private func reachForSocket() {
            guard !isClosed, socket == nil else { return }
            guard reaching == nil else {
                socketChangedWhileReaching = true
                return
            }
            guard let candidate = try? DebugDrawerSocketTransport(socketPath: socketPath) else { return }
            socketChangedWhileReaching = false
            reaching = Task { [weak self] in
                let isAgreed = await candidate.handshake()
                self?.reached(candidate, isAgreed: isAgreed)
            }
        }

        private func reached(_ candidate: DebugDrawerSocketTransport, isAgreed: Bool) {
            reaching = nil
            guard isAgreed, !isClosed else {
                candidate.close()
                // The socket was made again while this one failed: that one may answer.
                if socketChangedWhileReaching { reachForSocket() }
                return
            }
            adopt(candidate)
        }

        /// Switches to `adopted`: the commands still waiting in the store go over it first, then
        /// every plugin transport reads from it.
        private func adopt(_ adopted: DebugDrawerSocketTransport) {
            socket = adopted
            channel = .socket
            store.isReading = false
            let waiting = leftInStore
            leftInStore = []
            // Removing a command's file takes it from the app, which removes each before it
            // performs it: a file this removes, the app hasn't taken, and goes over the socket.
            for left in waiting where (try? FileManager.default.removeItem(at: left.file)) != nil {
                _ = adopted.send(command: left.message)
            }
            for relay in relays.values {
                relay.attach(to: adopted)
            }
            // The socket transport publishes on the main actor, from the task reading its stream.
            socketDisconnection = adopted.$isConnected.sink { [weak self, weak adopted] isConnected in
                MainActor.assumeIsolated {
                    guard !isConnected, let adopted else { return }
                    self?.fallBack(from: adopted)
                }
            }
        }

        /// Switches to the store once `lost` has gone: the commands it didn't acknowledge are
        /// left there first, then every plugin transport reads from it.
        private func fallBack(from lost: DebugDrawerSocketTransport) {
            guard socket === lost else { return }
            let unacknowledged = lost.unacknowledgedCommands
            socket = nil
            socketDisconnection = nil
            lost.close()
            channel = .store
            store.isReading = true
            if !unacknowledged.isEmpty {
                let count = unacknowledged.count
                Self.logger.info("Left \(count, privacy: .public) commands the app hadn't acknowledged in the store")
            }
            for message in unacknowledged {
                leaveInStore(message)
            }
            for relay in relays.values {
                relay.attach(to: store)
            }
            // The app may be listening again already, with its socket made before this heard.
            reachForSocket()
        }

        /// Sends `message`, a command, over the channel in use.
        private func send(_ message: TransportMessage) {
            guard !isClosed else { return }
            if let socket {
                if socket.send(command: message) { return }
                fallBack(from: socket)
            }
            leaveInStore(message)
        }

        private func leaveInStore(_ message: TransportMessage) {
            guard let file = store.leave(message) else { return }
            leftInStore.append((file, message))
            // The store keeps at most this many command files, removing the oldest first, so
            // older ones of this transport's are gone.
            let excess = leftInStore.count - AppGroupStoreLayout.maximumCommandFiles
            if excess > 0 {
                leftInStore.removeFirst(excess)
            }
        }

        private func release(_ token: UUID) {
            relays.removeValue(forKey: token)?.finish()
        }
    }
#else
    // The release stand-in: the same members, never connecting.

    /// Release builds connect to nothing: this stand-in's initializer throws
    /// ``DebugDrawerTransportError/unreachable``.
    @MainActor
    public final class DebugDrawerSidecarTransport: DebugDrawerTransport, ObservableObject {
        /// Always ``Channel/store``.
        @Published public private(set) var channel = Channel.store

        /// Throws ``DebugDrawerTransportError/unreachable``.
        ///
        /// - Parameters:
        ///   - socketPath: Ignored.
        ///   - storeDirectory: Ignored.
        /// - Throws: ``DebugDrawerTransportError/unreachable``, always.
        public init(socketPath: String, storeDirectory: URL) throws(DebugDrawerTransportError) {
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

extension DebugDrawerSidecarTransport {
    /// How a ``DebugDrawerSidecarTransport`` reaches the app.
    public enum Channel: Equatable, Sendable {
        /// The app's Unix domain socket: each snapshot as it changes, each command at once.
        case socket
        /// The app's app-group store: the last snapshots the app wrote, and commands waiting for
        /// it.
        case store
    }
}
