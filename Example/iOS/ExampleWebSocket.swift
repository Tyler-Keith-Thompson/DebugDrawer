import ExampleTestBench
import Foundation
import SwiftUI

// The macOS example has its own copy of this file: each app is its own module. The echo server
// is the test bench's (ExampleWebSocketServer), which both link.

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
        Task {
            guard await ExampleWebSocketServer.start(), let url = ExampleWebSocketServer.url else {
                status = "The echo server didn't start"
                return
            }
            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()
            self.task = task
            status = "Open"
        }
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
