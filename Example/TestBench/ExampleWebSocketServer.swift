import Foundation
import Network

/// A WebSocket echo server on the loopback interface, so the Network plugin's WebSocket log can be
/// tried offline: it sends each text or binary message back as it came and answers pings. The
/// test bench's WebSocket action and the WebSocket buttons start it on first use; launched with
/// `-WebSocketEchoServer`, an app starts it at launch.
@MainActor
public enum ExampleWebSocketServer {
    public nonisolated static let launchArgument = "-WebSocketEchoServer"
    /// The port it listens on, on 127.0.0.1.
    public nonisolated static let port: UInt16 = 8765
    public nonisolated static let url = URL(string: "ws://127.0.0.1:\(port)/echo")

    /// Starts the server when the app was launched with the argument; compiles in release too,
    /// where it starts the server as well, since it is the example's, not the drawer's.
    public static func startIfAsked() {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }
        Task { _ = await start() }
    }

    /// Starts the server unless it is running, and returns once it listens: true, or false when it
    /// can't (the port is taken, say).
    public static func start() async -> Bool {
        switch state {
        case .ready:
            return true
        case .failed:
            return false
        case let .starting(waiting):
            return await withCheckedContinuation { state = .starting(waiting + [$0]) }
        case .idle:
            guard let listener else {
                state = .failed
                return false
            }
            return await withCheckedContinuation { continuation in
                state = .starting([continuation])
                listener.stateUpdateHandler = { update in
                    switch update {
                    case .ready: Task { @MainActor in finishStarting(listening: true) }
                    case .failed, .cancelled: Task { @MainActor in finishStarting(listening: false) }
                    default: break
                    }
                }
                listener.start(queue: queue)
            }
        }
    }

    private enum State {
        case idle
        case starting([CheckedContinuation<Bool, Never>])
        case ready
        case failed
    }

    private static var state = State.idle

    private static func finishStarting(listening: Bool) {
        guard case let .starting(waiting) = state else { return }
        state = listening ? .ready : .failed
        waiting.forEach { $0.resume(returning: listening) }
    }

    private nonisolated static let queue = DispatchQueue(label: "ExampleWebSocketServer")

    /// The listener, made on first use and kept for the app's life.
    private nonisolated static let listener: NWListener? = {
        let parameters = NWParameters.tcp
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.autoReplyPing = true
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
        let listener = try? NWListener(using: parameters)
        listener?.newConnectionHandler = { connection in
            connection.start(queue: queue)
            echo(connection)
        }
        return listener
    }()

    private nonisolated static func echo(_ connection: NWConnection) {
        connection.receiveMessage { content, context, _, error in
            guard error == nil,
                  let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
            else { return }
            let reply = NWConnection.ContentContext(identifier: "echo", metadata: [NWProtocolWebSocket.Metadata(opcode: metadata.opcode)])
            connection.send(content: content ?? Data(), contentContext: reply, isComplete: true, completion: .contentProcessed { _ in
                echo(connection)
            })
        }
    }
}
