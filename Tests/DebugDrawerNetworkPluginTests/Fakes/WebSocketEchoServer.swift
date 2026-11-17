#if DEBUG
    import Foundation
    import Network
    import os

    /// A loopback WebSocket server for the WebSocket tests. It sends each text or binary message
    /// back as it came and answers pings with pongs, except two text commands:
    ///
    /// - `close <code> <reason>` closes the connection with that code and reason;
    /// - `drop` drops the connection with no close frame.
    final class WebSocketEchoServer: Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "WebSocketEchoServer")

        init() throws {
            let parameters = NWParameters.tcp
            let webSocket = NWProtocolWebSocket.Options()
            webSocket.autoReplyPing = true
            parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
        }

        func start() async throws -> UInt16 {
            listener.newConnectionHandler = { [queue] connection in
                connection.start(queue: queue)
                Self.echo(connection)
            }
            return try await withCheckedThrowingContinuation { continuation in
                let resumed = OSAllocatedUnfairLock(initialState: false)
                listener.stateUpdateHandler = { [listener] state in
                    let claim = { resumed.withLock { wasResumed in
                        defer { wasResumed = true }
                        return !wasResumed
                    } }
                    switch state {
                    case .ready:
                        if let port = listener.port?.rawValue, claim() { continuation.resume(returning: port) }
                    case let .failed(error):
                        if claim() { continuation.resume(throwing: error) }
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            }
        }

        func stop() {
            listener.cancel()
        }

        /// Reads one message, answers it, then reads the next, until the connection ends.
        private static func echo(_ connection: NWConnection) {
            connection.receiveMessage { content, context, _, error in
                guard error == nil,
                      let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
                else { return }
                let data = content ?? Data()
                if metadata.opcode == .text, let command = String(data: data, encoding: .utf8) {
                    if command == "drop" {
                        connection.forceCancel()
                        return
                    }
                    if command.hasPrefix("close ") {
                        close(connection, command: command)
                        return
                    }
                }
                let reply = NWProtocolWebSocket.Metadata(opcode: metadata.opcode)
                let replyContext = NWConnection.ContentContext(identifier: "echo", metadata: [reply])
                connection.send(content: data, contentContext: replyContext, isComplete: true, completion: .contentProcessed { _ in
                    echo(connection)
                })
            }
        }

        /// Sends a close frame with the code and reason in `close <code> <reason>`.
        private static func close(_ connection: NWConnection, command: String) {
            let parts = command.split(separator: " ", maxSplits: 2).map(String.init)
            let code = parts.count > 1 ? UInt16(parts[1]) ?? 1000 : 1000
            let reason = parts.count > 2 ? parts[2] : ""
            let close = NWProtocolWebSocket.Metadata(opcode: .close)
            let defined = NWProtocolWebSocket.CloseCode.Defined(rawValue: code) ?? .normalClosure
            close.closeCode = code >= 4000 ? .privateCode(code) : .protocolCode(defined)
            let context = NWConnection.ContentContext(identifier: "close", metadata: [close])
            connection.send(content: Data(reason.utf8), contentContext: context, isComplete: true, completion: .contentProcessed { _ in })
        }
    }
#endif
