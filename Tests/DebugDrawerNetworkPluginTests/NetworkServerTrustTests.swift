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
        @Test("The app's delegate checks a pinned certificate, with or without the plugin: rejected fails, accepted succeeds, none is untrusted")
        func pinnedCertificate() async throws {
            let server = try ScriptedServer(identity: SelfSignedIdentity.make()) { _ in
                "HTTP/1.1 200 OK\r\nContent-Length: 6\r\nConnection: close\r\n\r\nsecure"
            }
            defer { server.stop() }
            let port = try await server.start()
            let url = try #require(URL(string: "https://127.0.0.1:\(port)/pinned"))
            let arms: [(name: String, protocolClasses: [AnyClass])] = [("without", []), ("with", [DebugNetworkProtocol.self])]
            var actual: [String: [String]] = [:]

            for arm in arms {
                var outcome: [String] = []
                for decision in [PinningDelegate.Decision.reject, .accept, nil] {
                    let delegate = decision.map { PinningDelegate(pinned: SelfSignedIdentity.certificateData, decision: $0) }
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.protocolClasses = arm.protocolClasses
                    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
                    do {
                        let (data, response) = try await session.data(from: url)
                        outcome.append("\((response as? HTTPURLResponse)?.statusCode ?? 0) \((String(bytes: data, encoding: .utf8) ?? ""))")
                    } catch {
                        outcome.append("failed \((error as? URLError)?.code.rawValue ?? 0)")
                    }
                    outcome += delegate?.challenges ?? []
                    session.invalidateAndCancel()
                }
                actual[arm.name] = outcome
            }

            let expected = [
                "failed \(NSURLErrorCancelled)", "ServerTrust, pinned certificate",
                "200 secure", "ServerTrust, pinned certificate",
                "failed \(NSURLErrorServerCertificateUntrusted)"
            ]
            #expect(actual["without"] == expected)
            #expect(actual["with"] == expected)
        }
    }

    /// An app's delegate that pins the server's certificate: it records each challenge it is
    /// asked, with whether the server's leaf certificate is the pinned one, and rejects or accepts
    /// the server's trust as told.
    private final class PinningDelegate: NSObject, URLSessionTaskDelegate, Sendable {
        enum Decision {
            case reject
            case accept
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
