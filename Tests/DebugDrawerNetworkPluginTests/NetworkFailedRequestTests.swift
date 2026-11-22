#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    // These requests go through the URL protocol, which reads the process's one set of mock rules
    // and conditions, so they are part of the mock interception suite, which is serialized: no
    // other test's rules answer them.
    extension NetworkMockInterceptionTests {
        @Test("A request to a host that never resolves is listed complete, with error -1003, as a failure, under Errors")
        func unresolvableHostListed() async throws {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            // `.invalid` never resolves (RFC 6761), and no rule or condition answers it.
            let address = "https://nowhere.invalid/\(UUID().uuidString)"
            let url = try #require(URL(string: address))
            let logged = NetworkStore.shared.$entries.values
            let expectedCode = URLError.Code.cannotFindHost

            var thrown: URLError?
            do {
                _ = try await session.data(from: url)
            } catch let error as URLError {
                thrown = error
            }

            var entry: NetworkEntry?
            for await entries in logged {
                if let match = entries.first(where: { $0.url == address && $0.isComplete }) {
                    entry = match
                    break
                }
            }
            let actual = try #require(entry)
            let errorsFilter = NetworkStore.entries(NetworkStore.shared.entries, matching: .errors, text: "")
            #expect(thrown?.code == expectedCode)
            // The log keeps what URL loading said of the error, which the app's task was handed.
            #expect(actual.error == thrown?.localizedDescription)
            #expect(actual.error != nil)
            #expect(actual.statusCode == nil)
            #expect(actual.isFailure)
            #expect(errorsFilter.contains { $0.id == actual.id })
            session.invalidateAndCancel()
        }

        @Test("A 404 from the server is listed complete with its status and body, as a failure, under 4xx and Errors")
        func notFoundListed() async throws {
            let server = try ScriptedServer { _ in
                "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 9\r\nConnection: close\r\n\r\nnot found"
            }
            defer { server.stop() }
            let port = try await server.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [DebugNetworkProtocol.self]
            let session = URLSession(configuration: configuration)
            let address = "http://127.0.0.1:\(port)/missing/\(UUID().uuidString)"
            let url = try #require(URL(string: address))
            let logged = NetworkStore.shared.$entries.values
            let expectedStatus = 404
            let expectedBody = Data("not found".utf8)

            let (data, response) = try await session.data(from: url)

            var entry: NetworkEntry?
            for await entries in logged {
                if let match = entries.first(where: { $0.url == address && $0.isComplete }) {
                    entry = match
                    break
                }
            }
            let actual = try #require(entry)
            let clientErrors = NetworkStore.entries(NetworkStore.shared.entries, matching: .clientError, text: "")
            let errorsFilter = NetworkStore.entries(NetworkStore.shared.entries, matching: .errors, text: "")
            #expect((response as? HTTPURLResponse)?.statusCode == expectedStatus)
            #expect(data == expectedBody)
            #expect(actual.statusCode == expectedStatus)
            #expect(actual.response?.data == expectedBody)
            #expect(actual.error == nil)
            #expect(actual.isFailure)
            #expect(clientErrors.contains { $0.id == actual.id })
            #expect(errorsFilter.contains { $0.id == actual.id })
            session.invalidateAndCancel()
        }
    }
#endif
