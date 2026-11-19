import Combine
import DebugDrawer
import Foundation
import Network

// The viewer's end of the network transport: one TCP connection to a device's
// `DebugDrawerNetworkServer`. It asks to pair as it connects, then waits for the person to type
// the code the device shows; once the device accepts, it hands core's messages to `RemoteModels`,
// as the socket transport does, so a plugin's view draws the same over either. A plugin connected
// before pairing finishes waits for it: its subscribe is held until the device accepts, since a
// device closes a connection that sends one sooner.

#if DEBUG
    /// A `DebugDrawerTransport` to the models of an app on another device, over the
    /// network, once paired with the code that device shows.
    ///
    /// ```swift
    /// let device = DebugDrawerNetworkTransport(endpoint: found.endpoint, viewerName: "Studio Mac")
    /// // The device now shows a code beside "Studio Mac"; the person types it here.
    /// try await device.pair(code: typedCode)
    /// let network = try await device.connect(toPlugin: NetworkPlugin().id, snapshot: NetworkSnapshot.self, command: NetworkCommand.self)
    /// ```
    ///
    /// Release builds get a stand-in that fails with ``DebugDrawerPairingError/unreachable``.
    @MainActor
    public final class DebugDrawerNetworkTransport: DebugDrawerTransport, ObservableObject {
        /// How far pairing has got.
        public enum PairingState: Equatable, Sendable {
            /// Connecting, and asking to pair.
            case connecting
            /// The device shows a code: send it with ``DebugDrawerNetworkTransport/pair(code:)``.
            case waitingForCode
            /// Paired: plugins can be connected to.
            case paired
            /// Not paired, and never will be on this connection: make a new transport to try
            /// again.
            case failed(DebugDrawerPairingError)
        }

        private let connection: NetworkConnection
        private let models: RemoteModels
        /// Messages for the device held until it accepts.
        private var held: [TransportMessage] = []
        /// How far pairing has got.
        @Published public private(set) var pairingState = PairingState.connecting

        /// Connects to the device at `endpoint` and asks to pair as `viewerName`.
        ///
        /// - Parameters:
        ///   - endpoint: A ``DebugDrawerNetworkDevice/endpoint`` a browser found, or a host and
        ///     port.
        ///   - viewerName: The name the device shows beside the code, such as this Mac's name.
        public init(endpoint: NWEndpoint, viewerName: String) {
            let connection = NetworkConnection(NWConnection(to: endpoint, using: .tcp))
            self.connection = connection
            // The models send through this transport, which holds them: a relay set once both
            // exist breaks the cycle.
            let relay = MessageRelay()
            models = RemoteModels(subscribesOnConnect: true) { relay.send?($0) }
            relay.send = { [weak self] message in self?.deliver(message) }
            connection.send(PairingMessage(pairing: .request, viewerName: viewerName).encoded())
            Task { [weak self, models] in
                for await body in connection.frames {
                    self?.receive(body)
                }
                models.close()
                self?.connectionEnded()
            }
        }

        deinit {
            connection.close()
        }

        /// Sends the code the device shows, and returns once the device accepts it.
        ///
        /// - Parameter code: The six digits the device shows.
        /// - Throws: ``DebugDrawerPairingError/wrongCode`` when it isn't the device's code,
        ///   ``DebugDrawerPairingError/rejected`` when the person declined,
        ///   ``DebugDrawerPairingError/unreachable`` or ``DebugDrawerPairingError/disconnected``
        ///   when the connection fails, and ``DebugDrawerPairingError/cancelled`` when the task is
        ///   cancelled first.
        public func pair(code: String) async throws(DebugDrawerPairingError) {
            if case let .failed(error) = pairingState { throw error }
            guard pairingState != .paired else { return }
            connection.send(PairingMessage(pairing: .code, code: code).encoded())
            for await state in $pairingState.values {
                switch state {
                case .paired: return
                case let .failed(error): throw error
                case .connecting, .waitingForCode: continue
                }
            }
            throw .cancelled
        }

        /// The plugin's model on the device, once paired and once its first snapshot arrives.
        ///
        /// - Parameters:
        ///   - pluginID: The ID the model was registered under.
        ///   - snapshot: The model's `Snapshot` type.
        ///   - command: The model's `Command` type.
        /// - Returns: A transport showing the model's snapshots as they arrive and sending its
        ///   commands to the device.
        /// - Throws: `DebugDrawerTransportError.mismatchedTypes`,
        ///   `DebugDrawerTransportError.disconnected` (also when pairing fails) or
        ///   `DebugDrawerTransportError.cancelled`.
        public func connect<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>(
            toPlugin pluginID: String,
            snapshot: Snapshot.Type,
            command: Command.Type
        ) async throws(DebugDrawerTransportError) -> DebugDrawerPluginTransport<Snapshot, Command> {
            try await models.connect(toPlugin: pluginID, snapshot: snapshot, command: command, holding: self)
        }

        /// Disconnects from the device. The transports this handed out keep their last snapshot.
        public func close() {
            connection.close()
        }

        /// Sends `message` to the device now if paired, or once it is.
        private func deliver(_ message: TransportMessage) {
            if pairingState == .paired {
                connection.send(message)
            } else {
                held.append(message)
            }
        }

        /// Takes in a frame: a pairing message until the device accepts, core's messages after.
        private func receive(_ body: Data) {
            guard pairingState != .paired else {
                if let message = TransportMessage.decoded(from: body) { models.receive(message) }
                return
            }
            guard let message = PairingMessage.decoded(from: body) else { return }
            switch message.pairing {
            case .waitingForCode:
                pairingState = .waitingForCode
            case .accepted:
                pairingState = .paired
                for message in held {
                    connection.send(message)
                }
                held = []
            case .rejected:
                pairingState = .failed(message.rejection == .wrongCode ? .wrongCode : .rejected)
            case .request, .code:
                break
            }
        }

        /// The connection closed: pairing, if not over, failed.
        private func connectionEnded() {
            held = []
            switch pairingState {
            case .connecting: pairingState = .failed(.unreachable)
            case .waitingForCode, .paired: pairingState = .failed(.disconnected)
            case .failed: break
            }
        }
    }

    /// Where the models' messages go, set once the transport exists.
    @MainActor
    private final class MessageRelay {
        var send: (@MainActor (TransportMessage) -> Void)?
    }
#else
    // The release stand-in: the same members, never connecting.

    /// Release builds connect to nothing: this stand-in's pairing fails with
    /// ``DebugDrawerPairingError/unreachable``.
    @MainActor
    public final class DebugDrawerNetworkTransport: DebugDrawerTransport, ObservableObject {
        /// How far pairing has got.
        public enum PairingState: Equatable, Sendable {
            /// Connecting, and asking to pair.
            case connecting
            /// The device shows a code.
            case waitingForCode
            /// Paired.
            case paired
            /// Not paired.
            case failed(DebugDrawerPairingError)
        }

        /// Always ``PairingState/failed(_:)`` with ``DebugDrawerPairingError/unreachable``.
        @Published public private(set) var pairingState = PairingState.failed(.unreachable)

        /// A transport that connects to nothing.
        ///
        /// - Parameters:
        ///   - endpoint: Ignored.
        ///   - viewerName: Ignored.
        public init(endpoint: NWEndpoint, viewerName: String) {}

        /// Throws ``DebugDrawerPairingError/unreachable``.
        ///
        /// - Parameter code: Ignored.
        /// - Throws: ``DebugDrawerPairingError/unreachable``, always.
        public func pair(code: String) async throws(DebugDrawerPairingError) {
            throw .unreachable
        }

        /// Throws `DebugDrawerTransportError.unreachable`.
        ///
        /// - Parameters:
        ///   - pluginID: Ignored.
        ///   - snapshot: Ignored.
        ///   - command: Ignored.
        /// - Returns: Never.
        /// - Throws: `DebugDrawerTransportError.unreachable`, always.
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
