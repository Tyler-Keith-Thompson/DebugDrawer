#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import os
    import Testing

    // These requests go through the URL protocol, which reads the process's one set of mock rules,
    // so they are part of the mock interception suite, which is serialized: no other test's rules
    // answer them.
    extension NetworkMockInterceptionTests {
        @Test("The app's delegate decides a redirect, with or without the plugin: refused, the app gets the 302 alone; followed, the target")
        func redirectDecidedByApp() async throws {
            let server = try ScriptedServer { request in
                request.path == "/start"
                    ? "HTTP/1.1 302 Found\r\nLocation: /target\r\nContent-Length: 5\r\nConnection: close\r\n\r\nmoved"
                    : "HTTP/1.1 200 OK\r\nContent-Length: 7\r\nConnection: close\r\n\r\narrived"
            }
            defer { server.stop() }
            let port = try await server.start()
            let url = try #require(URL(string: "http://127.0.0.1:\(port)/start"))
            let arms: [(name: String, protocolClasses: [AnyClass])] = [("without", []), ("with", [DebugNetworkProtocol.self])]
            var actual: [String: [String]] = [:]

            for arm in arms {
                var outcome: [String] = []
                for follows in [false, true] {
                    let delegate = RedirectDelegate(follows: follows)
                    let configuration = URLSessionConfiguration.ephemeral
                    configuration.protocolClasses = arm.protocolClasses
                    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
                    let requestsBefore = server.requests.count
                    let (data, response) = try await session.data(from: url)
                    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                    outcome.append("\(status) \((String(bytes: data, encoding: .utf8) ?? "")) from \(response.url?.path ?? "")")
                    outcome += delegate.asked
                    outcome.append("server: " + server.requests.dropFirst(requestsBefore).map(\.path).joined(separator: " "))
                    session.invalidateAndCancel()
                }
                actual[arm.name] = outcome
            }

            let expected = [
                "302 moved from /start", "asked to follow to /target", "server: /start",
                "200 arrived from /target", "asked to follow to /target", "server: /start /target"
            ]
            #expect(actual["without"] == expected)
            #expect(actual["with"] == expected)
        }
    }

    /// An app's delegate that follows or refuses every redirect, recording each it is asked about.
    private final class RedirectDelegate: NSObject, URLSessionTaskDelegate, Sendable {
        private let follows: Bool
        private let questions = OSAllocatedUnfairLock<[String]>(initialState: [])

        init(follows: Bool) {
            self.follows = follows
        }

        var asked: [String] {
            questions.withLock { $0 }
        }

        func urlSession(
            _: URLSession,
            task _: URLSessionTask,
            willPerformHTTPRedirection _: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping @Sendable (URLRequest?) -> Void
        ) {
            questions.withLock { $0.append("asked to follow to \(request.url?.path ?? "")") }
            completionHandler(follows ? request : nil)
        }
    }
#endif
