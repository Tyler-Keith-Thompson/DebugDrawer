import Foundation
import Network
import Synchronization

/// An HTTP/1.1 server on 127.0.0.1 that answers every GET with the same JSON body, keeping each
/// connection alive, so a benchmark's requests never leave the machine.
final class LoopbackHTTPServer: Sendable {
    /// A small feed of three items: what the server answers unless given a body.
    static let smallBody = Data(#"{"items":[{"id":1,"title":"First"},{"id":2,"title":"Second"},{"id":3,"title":"Third"}],"next":null}"#.utf8)

    private let queue = DispatchQueue(label: "LoopbackHTTPServer")
    /// The whole response every request gets: the head, then the body.
    private let response: Data

    /// A server that answers every request with `body`, as JSON.
    init(body: Data = smallBody) {
        let head = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\n\r\n"
        response = Data(head.utf8) + body
    }
    /// The running listener and the URL it answers; `nil` until `start()` returns.
    private let running = Mutex<(listener: NWListener, url: URL)?>(nil)

    /// The URL every request goes to.
    ///
    /// Traps before `start()` has returned; the benchmarks read it only after their setup awaited it.
    var url: URL {
        running.withLock { $0 }!.url
    }

    /// Starts listening on an ephemeral port, and returns once the listener is ready.
    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
        let listener = try NWListener(using: parameters)
        let queue = queue
        let response = response
        listener.newConnectionHandler = { connection in
            connection.start(queue: queue)
            Self.answer(on: connection, with: response, buffered: Data())
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            listener.stateUpdateHandler = { [self] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    var components = URLComponents()
                    components.scheme = "http"
                    components.host = "127.0.0.1"
                    components.port = listener.port.map { Int($0.rawValue) }
                    components.path = "/feed"
                    // Trap: a scheme, a host and a path with no characters to escape always form a URL.
                    let url = components.url!
                    running.withLock { $0 = (listener, url) }
                    continuation.resume()
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

    private static let endOfHeaders = Data("\r\n\r\n".utf8)

    /// Answers each request read from `connection` (GETs, so a request ends with its headers) with
    /// `response`, then reads on until the client closes it.
    private static func answer(on connection: NWConnection, with response: Data, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            var buffer = buffered
            if let data {
                buffer.append(data)
            }
            while let end = buffer.range(of: endOfHeaders) {
                buffer.removeSubrange(..<end.upperBound)
                connection.send(content: response, completion: .idempotent)
            }
            guard !isComplete, error == nil else {
                connection.cancel()
                return
            }
            answer(on: connection, with: response, buffered: buffer)
        }
    }
}
