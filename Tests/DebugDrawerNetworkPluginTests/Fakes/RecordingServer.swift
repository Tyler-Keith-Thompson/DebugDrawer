#if DEBUG
    import Foundation
    import Network
    import os

    /// A loopback HTTP server for the interception tests. It answers every request with one
    /// small HTTP/1.1 200 response, keeping each request it read: its request line, headers
    /// (names lowercased) and body.
    final class RecordingServer: Sendable {
        struct Request: Sendable {
            var requestLine: String
            var headers: [String: String]
            var body: Data
        }

        private let listener: NWListener
        private let queue = DispatchQueue(label: "RecordingServer")
        private let received = OSAllocatedUnfairLock<[Request]>(initialState: [])

        init() throws {
            let parameters = NWParameters.tcp
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
        }

        /// The requests read, in order. The response is sent after the request is kept, so a
        /// client that has its response finds its request here.
        var requests: [Request] {
            received.withLock { $0 }
        }

        func start() async throws -> UInt16 {
            listener.newConnectionHandler = { [queue, received] connection in
                connection.start(queue: queue)
                Self.read(connection, buffer: Data()) { request in
                    received.withLock { $0.append(request) }
                    let body = #"{"ok":true}"#
                    let response = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n"
                        + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                    connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                        connection.cancel()
                    })
                }
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

        /// Reads until the headers and as many body bytes as `Content-Length` says have arrived.
        private static func read(_ connection: NWConnection, buffer: Data, completion: @escaping @Sendable (Request) -> Void) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { chunk, _, isComplete, error in
                var buffer = buffer
                if let chunk { buffer.append(chunk) }
                if let request = parse(buffer) {
                    completion(request)
                } else if !isComplete, error == nil {
                    read(connection, buffer: buffer, completion: completion)
                }
            }
        }

        private static func parse(_ data: Data) -> Request? {
            guard let end = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
            let head = (String(bytes: data[..<end.lowerBound], encoding: .utf8) ?? "").components(separatedBy: "\r\n")
            var headers: [String: String] = [:]
            for line in head.dropFirst() {
                guard let colon = line.firstIndex(of: ":") else { continue }
                headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
            let length = Int(headers["content-length"] ?? "0") ?? 0
            let body = data[end.upperBound...]
            guard body.count >= length else { return nil }
            return Request(requestLine: head.first ?? "", headers: headers, body: Data(body.prefix(length)))
        }
    }
#endif
