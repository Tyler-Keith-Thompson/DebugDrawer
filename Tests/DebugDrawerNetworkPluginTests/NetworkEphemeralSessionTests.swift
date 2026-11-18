#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    // These requests go through the URL protocol, which reads the process's one set of mock rules,
    // so they are part of the mock interception suite, which is serialized: no other test's rules
    // answer them. `NetworkAppSessions.install()` is what `installNetwork()` runs to note the
    // sessions the app makes from then on; it changes nothing else.
    extension NetworkMockInterceptionTests {
        @Test("An ephemeral session keeps its cookies and cached responses, with or without the plugin: the shared ones never get them")
        func ephemeralSessionKeepsItsStores() async throws {
            NetworkAppSessions.install()
            let cookieName = "ephemeral\(UUID().uuidString.replacingOccurrences(of: "-", with: ""))"
            let server = try ScriptedServer { request in
                if request.path.hasPrefix("/set") {
                    return "HTTP/1.1 200 OK\r\nSet-Cookie: \(cookieName)=1; Path=/\r\nCache-Control: max-age=600\r\n"
                        + "Content-Length: 3\r\nConnection: close\r\n\r\nset"
                }
                let cookie = request.headers["cookie"] ?? "no cookie"
                return "HTTP/1.1 200 OK\r\nContent-Length: \(cookie.utf8.count)\r\nConnection: close\r\n\r\n\(cookie)"
            }
            defer { server.stop() }
            let port = try await server.start()
            let arms: [(name: String, protocolClasses: [AnyClass])] = [("without", []), ("with", [DebugNetworkProtocol.self])]
            var actual: [String: [String]] = [:]

            for arm in arms {
                let configuration = URLSessionConfiguration.ephemeral
                configuration.protocolClasses = arm.protocolClasses
                let session = URLSession(configuration: configuration)
                let setURL = try #require(URL(string: "http://127.0.0.1:\(port)/set/\(arm.name)/\(cookieName)"))
                let echoURL = try #require(URL(string: "http://127.0.0.1:\(port)/echo/\(arm.name)/\(cookieName)"))

                _ = try await session.data(from: setURL)
                let (echoed, _) = try await session.data(from: echoURL)

                let sessionHasCookie = session.configuration.httpCookieStorage?.cookies?.contains { $0.name == cookieName } ?? false
                let sharedHasCookie = HTTPCookieStorage.shared.cookies?.contains { $0.name == cookieName } ?? false
                let sharedHasResponse = URLCache.shared.cachedResponse(for: URLRequest(url: setURL)) != nil
                actual[arm.name] = [
                    "sent back: \((String(bytes: echoed, encoding: .utf8) ?? ""))",
                    "session's cookie storage has it: \(sessionHasCookie)",
                    "shared cookie storage has it: \(sharedHasCookie)",
                    "shared cache has the response: \(sharedHasResponse)"
                ]
                session.invalidateAndCancel()
            }

            let expected = [
                "sent back: \(cookieName)=1",
                "session's cookie storage has it: true",
                "shared cookie storage has it: false",
                "shared cache has the response: false"
            ]
            #expect(actual["without"] == expected)
            #expect(actual["with"] == expected)
        }
    }
#endif
