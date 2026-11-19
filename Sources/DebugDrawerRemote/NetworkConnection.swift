import DebugDrawer
import Foundation
import Network
import os

// One TCP connection carrying core's frames: a 4-byte big-endian length, then that many bytes.
// Network.framework rather than core's POSIX `SocketConnection`: the viewer reaches a device by
// its Bonjour service, which `NWConnection` resolves itself, where a socket would need the C
// dns_sd API and an address picked by hand. What a frame holds (a pairing message, then core's
// `TransportMessage`s) is the caller's to decode, since which it is depends on whether the peer
// has paired yet.

#if DEBUG
    /// One connection to a peer, as the frames read from it and a way to send frames.
    final class NetworkConnection: Sendable {
        private static let logger = Logger(subsystem: "DebugDrawerRemote", category: "NetworkConnection")

        private let connection: NWConnection
        /// The body of each frame read, in order; it finishes when the peer closes, the connection
        /// fails or can't be made, or ``close()`` is called.
        let frames: AsyncStream<Data>

        /// Starts `connection` and reads it. A connection that can't reach its peer (refused, or
        /// waiting for a network) is closed rather than retried, so ``frames`` finishes.
        init(_ connection: NWConnection) {
            self.connection = connection
            let (frames, received) = AsyncStream<Data>.makeStream()
            self.frames = frames
            connection.stateUpdateHandler = { state in
                switch state {
                case .waiting, .failed:
                    connection.cancel()
                case .cancelled:
                    received.finish()
                default:
                    break
                }
            }
            connection.start(queue: DispatchQueue(label: "DebugDrawerRemote.NetworkConnection"))
            Self.read(connection, decoder: OSAllocatedUnfairLock(initialState: TransportFrameDecoder()), into: received)
        }

        deinit {
            connection.cancel()
        }

        /// Sends `body` as one frame, after every frame sent before it; with `thenClose`, closes
        /// the connection once it is sent, so the peer reads it before the end of the stream.
        func send(_ body: Data, thenClose: Bool = false) {
            let connection = connection
            connection.send(content: TransportFraming.frame(body: body), completion: .contentProcessed { error in
                if thenClose || error != nil {
                    connection.cancel()
                }
            })
        }

        /// Sends `message`, one of core's transport messages, as one frame.
        func send(_ message: TransportMessage) {
            guard let frame = try? TransportFraming.frame(message) else {
                Self.logger.error("Couldn't encode a message for \(message.pluginID, privacy: .public)")
                return
            }
            let connection = connection
            connection.send(content: frame, completion: .contentProcessed { error in
                if error != nil { connection.cancel() }
            })
        }

        /// Closes the connection: ``frames`` finishes, and nothing more is sent.
        func close() {
            connection.cancel()
        }

        /// Reads what arrives and yields the frames it completes, until the stream ends or isn't
        /// this format. Static, so the pending receive holds the connection and not this object.
        private static func read(
            _ connection: NWConnection,
            decoder: OSAllocatedUnfairLock<TransportFrameDecoder>,
            into received: AsyncStream<Data>.Continuation
        ) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { data, _, isComplete, error in
                if let data, !data.isEmpty {
                    // A Result rather than a do/catch around `withLock`: built -O, that crashed
                    // swift-frontend's CopyPropagation pass ("Found a leaked owned value": the
                    // error's `any Error` box) in Swift 6.4.0 and 6.4.2 (DD-249).
                    let decoded = decoder.withLock { decoder in
                        Result { () throws(TransportFrameDecoder.FrameTooLong) in try decoder.append(data) }
                    }
                    guard case let .success(bodies) = decoded else {
                        logger.error("Closed a connection that sent a frame longer than the format allows")
                        connection.cancel()
                        return
                    }
                    for body in bodies {
                        received.yield(body)
                    }
                }
                guard !isComplete, error == nil else {
                    connection.cancel()
                    return
                }
                read(connection, decoder: decoder, into: received)
            }
        }
    }
#endif
