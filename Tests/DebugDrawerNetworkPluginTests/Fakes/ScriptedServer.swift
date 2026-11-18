#if DEBUG
    import Foundation
    import Network
    import os

    /// A loopback HTTP/1.1 server for the tests of how the app's session behaves with the plugin
    /// installed: it answers each request with the raw response its script gives for the request's
    /// path, over TLS when it has an identity, and keeps each request's line and headers (names
    /// lowercased). Every connection is closed after one response.
    final class ScriptedServer: Sendable {
        struct Request: Sendable {
            var path: String
            var headers: [String: String]
        }

        private let listener: NWListener
        private let queue = DispatchQueue(label: "ScriptedServer")
        private let script: @Sendable (Request) -> String
        private let received = OSAllocatedUnfairLock<[Request]>(initialState: [])

        /// - Parameters:
        ///   - identity: The certificate and key to serve TLS with; `nil` for plain HTTP.
        ///   - script: The whole response, status line to body, for each request.
        init(identity: SecIdentity? = nil, script: @escaping @Sendable (Request) -> String) throws {
            let parameters: NWParameters
            if let identity, let secIdentity = sec_identity_create(identity) {
                let tls = NWProtocolTLS.Options()
                sec_protocol_options_set_local_identity(tls.securityProtocolOptions, secIdentity)
                parameters = NWParameters(tls: tls)
            } else {
                parameters = .tcp
            }
            parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
            listener = try NWListener(using: parameters)
            self.script = script
        }

        /// The requests read, in order. A response is sent after its request is kept.
        var requests: [Request] {
            received.withLock { $0 }
        }

        func start() async throws -> UInt16 {
            listener.newConnectionHandler = { [queue, received, script] connection in
                connection.start(queue: queue)
                Self.read(connection, buffer: Data()) { request in
                    received.withLock { $0.append(request) }
                    connection.send(content: Data(script(request).utf8), completion: .contentProcessed { _ in
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

        /// Reads until the end of the headers; these tests send no bodies.
        private static func read(_ connection: NWConnection, buffer: Data, completion: @escaping @Sendable (Request) -> Void) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { chunk, _, isComplete, error in
                var buffer = buffer
                if let chunk { buffer.append(chunk) }
                if let end = buffer.range(of: Data("\r\n\r\n".utf8)) {
                    let head = (String(bytes: buffer[..<end.lowerBound], encoding: .utf8) ?? "").components(separatedBy: "\r\n")
                    var headers: [String: String] = [:]
                    for line in head.dropFirst() {
                        guard let colon = line.firstIndex(of: ":") else { continue }
                        headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    }
                    let path = head.first?.split(separator: " ").dropFirst().first.map(String.init) ?? ""
                    completion(Request(path: path, headers: headers))
                } else if !isComplete, error == nil {
                    read(connection, buffer: buffer, completion: completion)
                }
            }
        }
    }
#endif
