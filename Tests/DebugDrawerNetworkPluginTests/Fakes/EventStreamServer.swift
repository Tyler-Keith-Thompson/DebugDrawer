#if DEBUG
    import Foundation
    import Network

    /// A loopback HTTP/1.1 server of Server-Sent Events, for the tests of a stream held open
    /// through the plugin: it answers each request with a `text/event-stream` head and no length,
    /// then holds the connection open, sending what the test hands it, until the test finishes it.
    final class EventStreamServer: Sendable {
        /// One request's open stream, which the test writes events to and then closes.
        struct Stream: Sendable {
            /// The request's line, such as `GET /events HTTP/1.1`.
            let requestLine: String
            fileprivate let connection: NWConnection

            /// Sends `text` on the open connection as it is.
            func send(_ text: String) {
                connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in })
            }

            /// Ends the body, as a stream's server does when it closes: once what was sent before
            /// has gone, the connection closes.
            func finish() {
                connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { [connection] _ in
                    connection.cancel()
                })
            }
        }

        private let listener: NWListener
        private let queue = DispatchQueue(label: "EventStreamServer")
        private let streams: AsyncStream<Stream>
        private let accepted: AsyncStream<Stream>.Continuation

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            (streams, accepted) = AsyncStream.makeStream()
        }

        func start() async throws -> UInt16 {
            listener.newConnectionHandler = { [queue, accepted] connection in
                connection.start(queue: queue)
                Self.readHead(connection, buffer: Data()) { requestLine in
                    let head = "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\n"
                        + "X-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
                    connection.send(content: Data(head.utf8), completion: .contentProcessed { _ in
                        accepted.yield(Stream(requestLine: requestLine, connection: connection))
                    })
                }
            }
            return try await withCheckedThrowingContinuation { continuation in
                listener.stateUpdateHandler = { [listener] state in
                    switch state {
                    case .ready:
                        if let port = listener.port?.rawValue {
                            listener.stateUpdateHandler = nil
                            continuation.resume(returning: port)
                        }
                    case let .failed(error):
                        listener.stateUpdateHandler = nil
                        continuation.resume(throwing: error)
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            }
        }

        /// The next request's stream, once its head has been sent; `nil` once the server stopped.
        func nextStream() async -> Stream? {
            var iterator = streams.makeAsyncIterator()
            return await iterator.next()
        }

        func stop() {
            listener.cancel()
            accepted.finish()
        }

        /// Reads until the end of the request's headers, then hands over its first line; these
        /// tests send no bodies.
        private static func readHead(_ connection: NWConnection, buffer: Data, completion: @escaping @Sendable (String) -> Void) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { chunk, _, isComplete, error in
                var buffer = buffer
                if let chunk { buffer.append(chunk) }
                if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let head = String(bytes: buffer[..<end.lowerBound], encoding: .utf8) ?? ""
                    completion(head.components(separatedBy: "\r\n").first ?? "")
                } else if !isComplete, error == nil {
                    readHead(connection, buffer: buffer, completion: completion)
                } else {
                    connection.cancel()
                }
            }
        }
    }
#endif
