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
        /// The device's snapshots as they arrive, and what this build agreed with it.
        let models: RemoteModels
        /// Core's messages for the device, held until it accepts.
        private let outbox: PairedOutbox
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
            // The pairing request goes first: the models' hello, sent as they're made, waits in
            // the outbox for the device to accept.
            connection.send(PairingMessage(pairing: .request, viewerName: viewerName).encoded())
            let outbox = PairedOutbox(connection: connection)
            self.outbox = outbox
            models = RemoteModels(link: .stream) {
                outbox.send($0)
            } disconnect: {
                connection.close()
            }
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
        ///   `DebugDrawerTransportError.disconnected` (also when pairing fails),
        ///   `DebugDrawerTransportError.cancelled`, or
        ///   `DebugDrawerTransportError.incompatibleVersion` when the device's protocol version is
        ///   two or more major versions from this build's.
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
                outbox.open()
            case .rejected:
                pairingState = .failed(message.rejection == .wrongCode ? .wrongCode : .rejected)
            case .request, .code:
                break
            }
        }

        /// The connection closed: pairing, if not over, failed.
        private func connectionEnded() {
            outbox.discard()
            switch pairingState {
            case .connecting: pairingState = .failed(.unreachable)
            case .waitingForCode, .paired: pairingState = .failed(.disconnected)
            case .failed: break
            }
        }
    }

    /// Core's messages for the device: held until it accepts, sent at once after. Apart from the
    /// transport, so the models it holds can send through it without holding the transport.
    @MainActor
    private final class PairedOutbox {
        private enum State {
            /// The device hasn't accepted: these wait, oldest first.
            case holding([TransportMessage])
            /// The device accepted: each message goes at once.
            case open
        }

        private let connection: NetworkConnection
        private var state = State.holding([])

        init(connection: NetworkConnection) {
            self.connection = connection
        }

        /// Sends `message` now if the device has accepted, or once it does.
        func send(_ message: TransportMessage) {
            switch state {
            case let .holding(held): state = .holding(held + [message])
            case .open: connection.send(message)
            }
        }

        /// The device accepted: sends what was held, then each message as it comes.
        func open() {
            if case let .holding(held) = state {
                for message in held {
                    connection.send(message)
                }
            }
            state = .open
        }

        /// The connection ended: drops what was held.
        func discard() {
            if case .holding = state { state = .holding([]) }
        }
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
