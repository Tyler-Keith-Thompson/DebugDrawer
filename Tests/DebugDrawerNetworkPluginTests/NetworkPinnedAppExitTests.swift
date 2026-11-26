// What an app that pins certificates or holds a stream open can count on, pinned in child
// processes: installing registers the URL protocol, swizzles every session configuration and sets
// the process's bypassed hosts and body limit, and a session made before installNetwork() can only
// be made in a process that hasn't run it yet. It is in a file of its own, as exit tests need one.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import DebugDrawerTestSupport
    import Foundation
    import os
    import Testing

    @Suite("Apps that pin certificates or stream, in a child process", .timeLimit(.minutes(1)))
    struct NetworkPinnedAppExitTests {
        @Test("A session made before installNetwork() still sends its TLS challenge to the app's delegate, which decides it; both are captured")
        func sessionMadeBeforeInstall() async {
            await #expect(processExitsWith: .success) {
                useHomeFolderOfItsOwn()
                @MainActor
                func waitUntilLogged(_ urls: Set<String>) async -> [String: NetworkEntry] {
                    for await entries in NetworkStore.shared.$entries.values {
                        let complete = entries.filter { urls.contains($0.url) && $0.isComplete }
                        if Set(complete.map(\.url)) == urls {
                            return Dictionary(complete.map { ($0.url, $0) }, uniquingKeysWith: { first, _ in first })
                        }
                    }
                    return [:]
                }

                func check() async throws {
                    // Made before the plugin is installed, so it isn't among the sessions the
                    // plugin noted, and its requests are sent with the default configuration.
                    let rejecting = PinningDelegate(accepts: false)
                    let accepting = PinningDelegate(accepts: true)
                    let rejectingSession = URLSession(configuration: .ephemeral, delegate: rejecting, delegateQueue: nil)
                    let acceptingSession = URLSession(configuration: .ephemeral, delegate: accepting, delegateQueue: nil)
                    try await MainActor.run { try DebugDrawer.shared.installNetwork(sessions: .off) }
                    let server = try ScriptedServer(identity: SelfSignedIdentity.make()) { _ in
                        "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nsecure"
                    }
                    defer { server.stop() }
                    let port = try await server.start()
                    let rejectURL = try #require(URL(string: "https://127.0.0.1:\(port)/reject"))
                    let acceptURL = try #require(URL(string: "https://127.0.0.1:\(port)/accept"))

                    var rejected = "succeeded"
                    do {
                        _ = try await rejectingSession.data(from: rejectURL)
                    } catch {
                        rejected = "failed \((error as? URLError)?.code.rawValue ?? 0)"
                    }
                    let (data, response) = try await acceptingSession.data(from: acceptURL)
                    let logged = await waitUntilLogged([rejectURL.absoluteString, acceptURL.absoluteString])

                    #expect(rejected == "failed \(NSURLErrorCancelled)")
                    #expect(rejecting.challenges == ["127.0.0.1: ServerTrust, pinned certificate"])
                    #expect((response as? HTTPURLResponse)?.statusCode == 200)
                    #expect(String(bytes: data, encoding: .utf8) == "secure")
                    #expect(accepting.challenges == ["127.0.0.1: ServerTrust, pinned certificate"])
                    #expect(server.requests.map(\.path) == ["/accept"])
                    #expect(logged[rejectURL.absoluteString]?.statusCode == nil)
                    #expect(logged[rejectURL.absoluteString]?.error != nil)
                    #expect(logged[acceptURL.absoluteString]?.statusCode == 200)
                }
                try await check()
            }
        }

        @Test("A bypassed host and its subdomains skip the URL protocol: only the app's delegate decides, and nothing is logged or recorded")
        func bypassedHostPassesStraightThrough() async {
            await #expect(processExitsWith: .success) {
                useHomeFolderOfItsOwn()
                @MainActor
                func waitUntilLogged(_ url: String) async -> [NetworkEntry] {
                    for await entries in NetworkStore.shared.$entries.values where entries.contains(where: { $0.url == url && $0.isComplete }) {
                        return entries
                    }
                    return []
                }

                func takes(_ address: String) throws -> Bool {
                    try DebugNetworkProtocol.canInit(with: URLRequest(url: #require(URL(string: address))))
                }

                func check() async throws {
                    try await MainActor.run { try DebugDrawer.shared.installNetwork(bypassing: ["LocalHost"], sessions: .off) }
                    let server = try ScriptedServer(identity: SelfSignedIdentity.make()) { _ in
                        "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nsecure"
                    }
                    defer { server.stop() }
                    let port = try await server.start()
                    let delegate = PinningDelegate(accepts: true)
                    let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
                    let bypassedURL = try #require(URL(string: "https://localhost:\(port)/bypassed"))
                    let capturedURL = try #require(URL(string: "https://127.0.0.1:\(port)/captured"))
                    let token = "Bearer device-token"
                    var bypassedRequest = URLRequest(url: bypassedURL)
                    bypassedRequest.setValue(token, forHTTPHeaderField: "Authorization")

                    let (bypassedData, _) = try await session.data(for: bypassedRequest)
                    // Sent after the bypassed request ended: once it is logged, the bypassed one
                    // would have been too, had the plugin taken it.
                    _ = try await session.data(from: capturedURL)
                    let logged = await waitUntilLogged(capturedURL.absoluteString)
                    let bypassedSocket = try URLSession.shared.webSocketTask(with: #require(URL(string: "ws://api.localhost:1/socket")))
                    let recordedSocket = try URLSession.shared.webSocketTask(with: #require(URL(string: "ws://127.0.0.1:1/socket")))
                    defer {
                        bypassedSocket.cancel()
                        recordedSocket.cancel()
                    }

                    #expect(String(bytes: bypassedData, encoding: .utf8) == "secure")
                    #expect(server.requests.map(\.path) == ["/bypassed", "/captured"])
                    #expect(server.requests.first?.headers["authorization"] == token)
                    #expect(delegate.challenges == ["localhost: ServerTrust, pinned certificate", "127.0.0.1: ServerTrust, pinned certificate"])
                    #expect(logged.map(\.host) == ["127.0.0.1"])
                    #expect(try !takes("https://localhost/v1"))
                    #expect(try !takes("http://api.localhost:8080/v1"))
                    #expect(try takes("https://notlocalhost/v1"))
                    #expect(try takes("https://localhost.example.com/v1"))
                    #expect(NetworkWebSocketInterception.connectionID(of: bypassedSocket) == nil)
                    #expect(NetworkWebSocketInterception.connectionID(of: recordedSocket) != nil)
                }
                try await check()
            }
        }

        @Test("An SSE stream held open reaches the app event by event through the forwarding path; the log keeps its first bodyLimit bytes")
        func eventStreamHeldOpen() async {
            await #expect(processExitsWith: .success) {
                useHomeFolderOfItsOwn()
                @MainActor
                func waitUntilLogged(_ url: String, complete: Bool) async -> NetworkEntry? {
                    for await entries in NetworkStore.shared.$entries.values {
                        if let entry = entries.first(where: { $0.url == url && $0.isComplete == complete }) {
                            return entry
                        }
                    }
                    return nil
                }

                func check() async throws {
                    let bodyLimit = 64
                    try await MainActor.run { try DebugDrawer.shared.installNetwork(sessions: .off, bodyLimit: bodyLimit) }
                    let server = try EventStreamServer()
                    defer { server.stop() }
                    let port = try await server.start()
                    let url = try #require(URL(string: "http://127.0.0.1:\(port)/events"))
                    // Made after installNetwork(), so its requests are sent on a session made from
                    // its configuration.
                    let session = URLSession(configuration: .ephemeral)
                    let events = (1 ... 6).map { "data: event \($0) \(String(repeating: "x", count: 24))" }
                    let sent = events.map { "\($0)\n\n" }.joined()

                    // URL loading hands over the response with the body's first bytes, so the
                    // first event is sent before the response is awaited.
                    async let opened = session.bytes(from: url)
                    let stream = try #require(await server.nextStream())
                    stream.send("\(events[0])\n\n")
                    let (bytes, response) = try await opened
                    var lines = bytes.lines.makeAsyncIterator()
                    var heard: [String] = []
                    for (index, event) in events.enumerated() {
                        // Each event after the first is sent only once the app has read the one
                        // before, so each crosses the forwarding path while the stream is open.
                        if index > 0 {
                            stream.send("\(event)\n\n")
                        }
                        while let line = try await lines.next() {
                            if !line.isEmpty {
                                heard.append(line)
                                break
                            }
                        }
                    }
                    let whileOpen = await waitUntilLogged(url.absoluteString, complete: false)
                    stream.finish()
                    while try await lines.next() != nil {}
                    let completed = try #require(await waitUntilLogged(url.absoluteString, complete: true))

                    #expect(stream.requestLine == "GET /events HTTP/1.1")
                    #expect((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") == "text/event-stream")
                    #expect(heard == events)
                    #expect(whileOpen?.isComplete == false)
                    #expect(whileOpen?.responseBody == nil)
                    #expect(completed.statusCode == 200)
                    #expect(completed.error == nil)
                    #expect(completed.responseBody == Data(sent.utf8.prefix(bodyLimit)))
                    #expect(completed.responseBodySize == sent.utf8.count)
                    #expect(completed.isResponseBodyTruncated)
                }
                try await check()
            }
        }
    }

    /// An app's delegate that pins the server's certificate: it records each challenge it is
    /// asked, with the host and whether the server's leaf certificate is the pinned one, and
    /// rejects or accepts the server's trust as told.
    private final class PinningDelegate: NSObject, URLSessionTaskDelegate, Sendable {
        private let accepts: Bool
        private let asked = OSAllocatedUnfairLock<[String]>(initialState: [])

        init(accepts: Bool) {
            self.accepts = accepts
        }

        var challenges: [String] {
            asked.withLock { $0 }
        }

        func urlSession(
            _: URLSession,
            task _: URLSessionTask,
            didReceive challenge: URLAuthenticationChallenge,
            completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
        ) {
            let space = challenge.protectionSpace
            let leaf = space.serverTrust.flatMap { (SecTrustCopyCertificateChain($0) as? [SecCertificate])?.first }
            let isPinned = leaf.map { SecCertificateCopyData($0) as Data == SelfSignedIdentity.certificateData } ?? false
            let method = space.authenticationMethod.replacingOccurrences(of: "NSURLAuthenticationMethod", with: "")
            asked.withLock { $0.append("\(space.host): \(method), \(isPinned ? "pinned" : "other") certificate") }
            if accepts, isPinned, let trust = space.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
#endif
