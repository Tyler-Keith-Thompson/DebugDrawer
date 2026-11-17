import Foundation
import Network
import SwiftUI

// The iOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// A WebSocket echo server on the loopback interface, so the Network plugin's WebSocket log can be
/// tried offline: launched with `-WebSocketEchoServer`, the app starts it, and it sends each text
/// or binary message back as it came and answers pings.
enum ExampleWebSocketServer {
    static let launchArgument = "-WebSocketEchoServer"
    /// The port it listens on, on 127.0.0.1.
    static let port: UInt16 = 8765
    static let url = URL(string: "ws://127.0.0.1:\(port)/echo")

    /// Starts the server when the app was launched with the argument; compiles in release too,
    /// where it starts the server as well, since it is the example's, not the drawer's.
    static func startIfAsked() {
        guard ProcessInfo.processInfo.arguments.contains(launchArgument) else { return }
        listener?.start(queue: queue)
    }

    private static let queue = DispatchQueue(label: "ExampleWebSocketServer")

    /// The listener, made on first use and kept for the app's life.
    private static let listener: NWListener? = {
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

    private static func echo(_ connection: NWConnection) {
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

/// Buttons that open a WebSocket to the example's echo server, send it text and binary frames,
/// and close it, each with what came back.
struct ExampleWebSocketDemo: View {
    @State private var task: URLSessionWebSocketTask?
    @State private var status = "Not open"

    // A row each: in a List, the buttons of one row all fire on a tap anywhere in it.
    var body: some View {
        Button("Open WebSocket", action: open)
            .disabled(task != nil)
        Button("Send WebSocket Text") { send(.string(#"{"type":"chat","text":"Hello","token":"example-token"}"#)) }
            .disabled(task == nil)
        Button("Send WebSocket Binary") { send(.data(Data((0 ..< 24).map { UInt8($0 * 11 % 256) }))) }
            .disabled(task == nil)
        Button("Close WebSocket", action: close)
            .disabled(task == nil)
        Text(status)
            .foregroundStyle(.secondary)
            .accessibilityLabel("WebSocket: \(status)")
    }

    private func open() {
        guard let url = ExampleWebSocketServer.url else { return }
        guard ProcessInfo.processInfo.arguments.contains(ExampleWebSocketServer.launchArgument) else {
            status = "Launch with \(ExampleWebSocketServer.launchArgument) to start the echo server"
            return
        }
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        self.task = task
        status = "Open"
    }

    private func send(_ message: URLSessionWebSocketTask.Message) {
        guard let task else { return }
        Task {
            do {
                try await task.send(message)
                switch try await task.receive() {
                case let .string(text): status = "Echoed \(text.utf8.count) B of text"
                case let .data(data): status = "Echoed \(data.count) B of binary"
                @unknown default: status = "Echoed a message"
                }
            } catch {
                status = error.localizedDescription
            }
        }
    }

    private func close() {
        task?.cancel(with: .normalClosure, reason: Data("Done".utf8))
        task = nil
        status = "Closed with 1000 Normal closure"
    }
}
