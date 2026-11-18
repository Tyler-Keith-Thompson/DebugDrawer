import Foundation

/// Requests for the Network plugin: one that succeeds, one the server refuses, one that never
/// reaches a server, and a WebSocket conversation with the example's own echo server.
@MainActor
enum TestBenchNetwork {
    /// Answered with 200.
    static let page = "https://example.com/"
    /// A path example.com answers with 404.
    static let missingPage = "https://example.com/test-bench/missing"
    /// `.invalid` never resolves (RFC 2606), so the request fails before it reaches a server.
    static let unresolvableHost = "https://test-bench.invalid/"

    static func fetchPage() async -> String {
        await fetch(page)
    }

    static func fetchMissingPage() async -> String {
        await fetch(missingPage)
    }

    static func fetchUnresolvableHost() async -> String {
        await fetch(unresolvableHost)
    }

    /// Starts the echo server if it isn't running, opens a WebSocket to it, sends a text frame and a
    /// binary frame and reads each echo, pings, and closes with 1000.
    static func echoOverWebSocket() async -> String {
        guard await ExampleWebSocketServer.start(), let url = ExampleWebSocketServer.url else {
            return "The echo server didn't start"
        }
        let task = URLSession.shared.webSocketTask(with: url)
        task.resume()
        do {
            try await task.send(.string(#"{"type":"chat","text":"Hello from the test bench"}"#))
            _ = try await task.receive()
            try await task.send(.data(Data((0 ..< 24).map { UInt8($0 * 11 % 256) })))
            _ = try await task.receive()
            try await ping(task)
            task.cancel(with: .normalClosure, reason: Data("Done".utf8))
            return "Echoed text and binary, ponged, closed with 1000"
        } catch {
            task.cancel(with: .abnormalClosure, reason: nil)
            return error.localizedDescription
        }
    }

    private static func ping(_ task: URLSessionWebSocketTask) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            task.sendPing { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private static func fetch(_ address: String) async -> String {
        guard let url = URL(string: address) else { return "Not a URL" }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return "\(status), \(data.count) bytes"
        } catch {
            return error.localizedDescription
        }
    }
}
