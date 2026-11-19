#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import os
    import Testing

    // These requests go through the URL protocol, which reads the process's one set of mock rules,
    // so they are part of the mock interception suite, which is serialized: no other test's rules
    // answer them. The server serves a self-signed certificate made in memory, which no system
    // trusts: only the app's own delegate can let a request to it through.
    extension NetworkMockInterceptionTests {
        @Test("When the app's pinning delegate refuses, the server sees a connection but no request line or headers, with or without the plugin")
        func refusedPinSendsNothing() async throws {
            let token = "Bearer device-\(UUID().uuidString)"
            let arms: [(name: String, protocolClasses: [AnyClass])] = [("without", []), ("with", [DebugNetworkProtocol.self])]
            var actual: [String: [String]] = [:]

            for arm in arms {
                let server = try ScriptedServer(identity: SelfSignedIdentity.make()) { _ in
                    "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nsecure"
                }
                defer { server.stop() }
                let port = try await server.start()
                var outcome: [String] = []
                for decision in [PinningDelegate.Decision.reject, .accept] {
                    let delegate = PinningDelegate(pinned: SelfSignedIdentity.certificateData, decision: decision)
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.protocolClasses = arm.protocolClasses
                    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
                    var request = try URLRequest(url: #require(URL(string: "https://127.0.0.1:\(port)/\(decision)")))
                    request.setValue(token, forHTTPHeaderField: "Authorization")
                    do {
                        let (data, response) = try await session.data(for: request)
                        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                        outcome.append("\(decision): \(status) \(String(bytes: data, encoding: .utf8) ?? "")")
                    } catch {
                        outcome.append("\(decision): failed \((error as? URLError)?.code.rawValue ?? 0)")
                    }
                    outcome += delegate.challenges
                    if decision == .reject {
                        // The refused connection has ended on the server's side: what it carried
                        // past TLS is all the server will ever get from it.
                        let ended = await server.endedConnections(atLeast: 1)
                        outcome.append("refused connection carried \(ended.map(String.init).joined(separator: ", ")) bytes")
                        outcome.append("requests after refusing: \(server.requests.count)")
                    }
                    session.invalidateAndCancel()
                }
                let arrived = server.requests
                outcome.append("requests in all: \(arrived.map(\.path))")
                outcome.append("token arrived on: \(arrived.filter { $0.headers["authorization"] == token }.map(\.path))")
                actual[arm.name] = outcome
            }

            let expected = [
                "reject: failed \(NSURLErrorCancelled)", "ServerTrust, pinned certificate",
                "refused connection carried 0 bytes",
                "requests after refusing: 0",
                "accept: 200 secure", "ServerTrust, pinned certificate",
                "requests in all: [\"/accept\"]",
                "token arrived on: [\"/accept\"]"
            ]
            #expect(actual["without"] == expected)
            #expect(actual["with"] == expected)
        }
    }

    /// An app's delegate that pins the server's certificate: it records each challenge it is
    /// asked, with whether the server's leaf certificate is the pinned one, and rejects or accepts
    /// the server's trust as told.
    private final class PinningDelegate: NSObject, URLSessionTaskDelegate, Sendable {
        enum Decision: String, CustomStringConvertible {
            case reject
            case accept

            var description: String {
                rawValue
            }
        }

        private let pinned: Data
        private let decision: Decision
        private let asked = OSAllocatedUnfairLock<[String]>(initialState: [])

        init(pinned: Data, decision: Decision) {
            self.pinned = pinned
            self.decision = decision
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
            let method = challenge.protectionSpace.authenticationMethod.replacingOccurrences(of: "NSURLAuthenticationMethod", with: "")
            let trust = challenge.protectionSpace.serverTrust
            let leaf = trust.flatMap { (SecTrustCopyCertificateChain($0) as? [SecCertificate])?.first }
            let isPinned = leaf.map { SecCertificateCopyData($0) as Data == pinned } ?? false
            asked.withLock { $0.append("\(method), \(isPinned ? "pinned" : "other") certificate") }
            if decision == .accept, isPinned, let trust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.cancelAuthenticationChallenge, nil)
            }
        }
    }
#endif
