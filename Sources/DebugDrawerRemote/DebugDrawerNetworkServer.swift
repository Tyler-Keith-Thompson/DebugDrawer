import Combine
import DebugDrawer
import Foundation
import Network
import os

// The device's end of the network transport. Nothing listens or advertises until the app calls
// `start()`: making a server, or linking the module, does neither. Each connection must pair
// before it reaches a model: it asks with its name, the device shows a new six-digit code beside
// that name (wherever the app shows `pairingRequests`, such as a plugin of its own in the
// drawer), and the person types the code into the viewer. The right code pairs that
// one connection, which a `RegistrySession` (core's, the socket server's) then serves; any other
// message, a wrong code or the person's Reject closes it. A code is good for one try on one
// connection, so guessing means asking again, and each ask shows on the device. Trust ends with
// the connection: nothing is remembered, so a viewer pairs again after a relaunch. Rejected: an
// accept button alone (a person nearby could accept a stranger's Mac by mistake; typing the code
// proves the viewer is the person's), a code the device keeps for its run (one leaked code would
// let anyone in until relaunch), remembered viewers (a key store in a debug tool, and a device
// that trusts a Mac it once met), and TLS with the code as a pre-shared key (it would encrypt, but
// Network.framework's PSK options are C-level and the code exists only after the connection is
// made; debug builds on a developer's own network are the use).

#if DEBUG
    /// Serves a `DebugDrawerModelRegistry`'s models over TCP to viewers on other
    /// devices, each paired with a code this device shows.
    ///
    /// Nothing listens or advertises until ``start()``:
    ///
    /// ```swift
    /// let registry = DebugDrawerModelRegistry()
    /// registry.register(NetworkModel.shared, id: NetworkPlugin().id)
    /// registry.register(ConsoleModel.shared, id: ConsolePlugin().id)
    /// let server = DebugDrawerNetworkServer(registry: registry)
    /// try await server.start()
    /// ```
    ///
    /// A viewer that connects appears in ``pairingRequests`` with a code; show it, in a plugin
    /// of the app's own in the drawer for instance, and the viewer pairs when its person types
    /// it. Release builds get a stand-in that never listens.
    @MainActor
    public final class DebugDrawerNetworkServer: ObservableObject {
        private static let logger = Logger(subsystem: "DebugDrawerRemote", category: "DebugDrawerNetworkServer")
        /// The most requests shown at once; a viewer asking beyond them is turned away as busy.
        static let maximumPairingRequests = 4

        private let registry: DebugDrawerModelRegistry
        /// Where to listen and whether to advertise.
        public let configuration: DebugDrawerNetworkServerConfiguration
        private let listener: any ConnectionListener
        /// The port the server listens on, or `nil` while it doesn't.
        @Published public private(set) var port: UInt16?
        /// The viewers waiting for their code, oldest first.
        @Published public private(set) var pairingRequests: [DebugDrawerPairingRequest] = []
        /// The viewers paired, oldest first.
        @Published public private(set) var pairedViewers: [DebugDrawerPairedViewer] = []
        /// Each connection, from accepted until closed.
        private var viewers: [UUID: Viewer] = [:]
        /// Incremented by each start and stop, so a connection accepted by a listener since stopped
        /// is closed rather than served.
        private var generation = 0
        /// Whether a ``start()`` is waiting for the listener, so a second one waits on nothing.
        private var isStarting = false

        /// A server of `registry`'s models; it listens once started.
        ///
        /// - Parameters:
        ///   - registry: The models to serve.
        ///   - configuration: Where to listen, and whether to advertise over Bonjour.
        public convenience init(registry: DebugDrawerModelRegistry, configuration: DebugDrawerNetworkServerConfiguration = .init()) {
            self.init(registry: registry, configuration: configuration, listener: _ConnectionListener())
        }

        /// A server that listens through `listener`.
        init(registry: DebugDrawerModelRegistry, configuration: DebugDrawerNetworkServerConfiguration, listener: any ConnectionListener) {
            self.registry = registry
            self.configuration = configuration
            self.listener = listener
        }

        // A server dropped without `stop()` stops listening and disconnects its viewers, whose
        // read loops would hold their connections open otherwise.
        isolated deinit {
            listener.cancel()
            for viewer in viewers.values {
                viewer.close()
            }
        }

        /// Whether the server is listening.
        public var isRunning: Bool {
            port != nil
        }

        /// Listens, and advertises when the configuration says to, returning once listening.
        /// Does nothing while the server runs.
        ///
        /// - Throws: `DebugDrawerTransportError.cannotServe` when the system refuses
        ///   to listen (the port is taken, say).
        public func start() async throws(DebugDrawerTransportError) {
            guard port == nil, !isStarting else { return }
            isStarting = true
            defer { isStarting = false }
            generation += 1
            let started = generation
            let request = ListenerRequest(
                port: configuration.port,
                loopbackOnly: configuration.loopbackOnly,
                advertisement: configuration.advertises
                    ? .init(name: configuration.serviceName, txtRecord: DebugDrawerBonjourService.currentTXTRecord())
                    : nil
            )
            let listening = try await listener.listen(request) { [weak self] connection in
                Task { @MainActor in self?.accept(connection, generation: started) }
            }
            // Stopped while the listener started: it is cancelled already.
            guard started == generation else { return }
            port = listening
            Self.logger.info("Listening on port \(self.port ?? 0, privacy: .public)")
        }

        /// Stops listening and advertising, and disconnects every viewer. The server can start
        /// again.
        public func stop() {
            generation += 1
            listener.cancel()
            port = nil
            for viewer in viewers.values {
                viewer.close()
            }
            viewers = [:]
            pairingRequests = []
            pairedViewers = []
        }

        /// Declines `request`: the viewer is told so and disconnected.
        ///
        /// - Parameter request: One of ``pairingRequests``.
        public func reject(_ request: DebugDrawerPairingRequest) {
            guard let viewer = viewers[request.id] else { return }
            viewer.connection.send(PairingMessage(pairing: .rejected, rejection: .declined).encoded(), thenClose: true)
            drop(request.id)
        }

        /// Disconnects a paired viewer.
        ///
        /// - Parameter viewer: One of ``pairedViewers``.
        public func disconnect(_ viewer: DebugDrawerPairedViewer) {
            viewers[viewer.id]?.close()
            drop(viewer.id)
        }

        /// Serves `connection` until it closes, once it pairs.
        private func accept(_ connection: NWConnection, generation accepted: Int) {
            let connection = NetworkConnection(connection)
            guard accepted == generation else {
                connection.close()
                return
            }
            let id = UUID()
            viewers[id] = Viewer(connection: connection)
            Task { [weak self] in
                for await body in connection.frames {
                    self?.receive(body, from: id)
                }
                self?.drop(id)
            }
        }

        /// Takes in a frame from the viewer `id`, as its pairing stage reads it.
        private func receive(_ body: Data, from id: UUID) {
            guard let viewer = viewers[id] else { return }
            switch viewer.stage {
            case .connected:
                guard let message = PairingMessage.decoded(from: body), message.pairing == .request, let name = message.viewerName else {
                    return refuse(id, "sent something other than a pairing request")
                }
                guard pairingRequests.count < Self.maximumPairingRequests else {
                    viewer.connection.send(PairingMessage(pairing: .rejected, rejection: .busy).encoded(), thenClose: true)
                    return drop(id)
                }
                let request = DebugDrawerPairingRequest(id: id, viewerName: String(name.prefix(64)), code: Self.makeCode())
                viewer.stage = .waitingForCode(request)
                pairingRequests.append(request)
                viewer.connection.send(PairingMessage(pairing: .waitingForCode).encoded())
            case let .waitingForCode(request):
                guard let message = PairingMessage.decoded(from: body), message.pairing == .code else {
                    return refuse(id, "sent something other than a code")
                }
                pairingRequests.removeAll { $0.id == id }
                guard message.code == request.code else {
                    viewer.connection.send(PairingMessage(pairing: .rejected, rejection: .wrongCode).encoded(), thenClose: true)
                    return drop(id)
                }
                let connection = viewer.connection
                viewer.stage = .paired(RegistrySession(registry: registry) { connection.send($0) })
                pairedViewers.append(DebugDrawerPairedViewer(id: id, name: request.viewerName))
                connection.send(PairingMessage(pairing: .accepted).encoded())
                Self.logger.info("Paired with a viewer")
            case let .paired(session):
                guard let message = TransportMessage.decoded(from: body) else { return }
                session.receive(message)
            }
        }

        /// Closes the viewer `id`, which broke the handshake.
        private func refuse(_ id: UUID, _ reason: StaticString) {
            Self.logger.notice("Closed a connection that \(reason, privacy: .public)")
            viewers[id]?.close()
            drop(id)
        }

        /// Forgets the viewer `id`, closed or closing.
        private func drop(_ id: UUID) {
            viewers.removeValue(forKey: id)?.stopServing()
            pairingRequests.removeAll { $0.id == id }
            pairedViewers.removeAll { $0.id == id }
        }

        /// Six random digits, from the system's secure generator.
        private static func makeCode() -> String {
            var generator = SystemRandomNumberGenerator()
            let digits = (0 ..< 6).map { _ in String(Int.random(in: 0 ... 9, using: &generator)) }
            return digits.joined()
        }
    }

    /// One connection the server holds, and how far it got in pairing.
    @MainActor
    private final class Viewer {
        enum Stage {
            /// Connected, its request not in yet.
            case connected
            /// The device shows the request's code; the viewer must send it.
            case waitingForCode(DebugDrawerPairingRequest)
            /// Paired: the session serves it the registry's models.
            case paired(RegistrySession)
        }

        let connection: NetworkConnection
        var stage = Stage.connected

        init(connection: NetworkConnection) {
            self.connection = connection
        }

        /// Stops serving models, if it was.
        func stopServing() {
            if case let .paired(session) = stage { session.close() }
        }

        /// Stops serving and closes the connection.
        func close() {
            stopServing()
            connection.close()
        }
    }
#else
    // The release stand-in: the same members, never listening.

    /// Release builds serve nothing: this stand-in never listens or advertises.
    @MainActor
    public final class DebugDrawerNetworkServer: ObservableObject {
        /// Where the server would listen.
        public let configuration: DebugDrawerNetworkServerConfiguration
        /// Always `nil`.
        @Published public private(set) var port: UInt16?
        /// Always empty.
        @Published public private(set) var pairingRequests: [DebugDrawerPairingRequest] = []
        /// Always empty.
        @Published public private(set) var pairedViewers: [DebugDrawerPairedViewer] = []

        /// A server that never listens.
        ///
        /// - Parameters:
        ///   - registry: Ignored.
        ///   - configuration: Kept, and never used.
        public init(registry: DebugDrawerModelRegistry, configuration: DebugDrawerNetworkServerConfiguration = .init()) {
            self.configuration = configuration
        }

        /// Always `false`.
        public var isRunning: Bool {
            false
        }

        /// Does nothing.
        public func start() async throws(DebugDrawerTransportError) {}

        /// Does nothing.
        public func stop() {}

        /// Does nothing.
        ///
        /// - Parameter request: Ignored.
        public func reject(_ request: DebugDrawerPairingRequest) {}

        /// Does nothing.
        ///
        /// - Parameter viewer: Ignored.
        public func disconnect(_ viewer: DebugDrawerPairedViewer) {}
    }
#endif
