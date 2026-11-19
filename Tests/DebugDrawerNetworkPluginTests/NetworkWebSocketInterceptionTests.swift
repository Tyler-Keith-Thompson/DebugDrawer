#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    // Each test talks to a loopback echo server through a real URLSessionWebSocketTask, after
    // installing the WebSocket interception alone: installing the whole plugin would also swizzle
    // every session configuration in the test process. The interception records a frame before it
    // hands the app its completion, so each test reads the shared recorder as soon as its send or
    // receive returns, finding its own connection by the id kept on its task. That installing
    // changes nothing until it is called, and that the app gets what it would get without it, are
    // pinned in a child process (NetworkWebSocketExitTests).
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkWebSocketInterceptionTests {
        @Test("Text sent and echoed back is listed under one connection, the sent frame then the received one, with their times")
        func textEcho() async throws {
            await MainActor.run { NetworkWebSocketInterception.install() }
            let server = try WebSocketEchoServer()
            defer { server.stop() }
            let port = try await server.start()
            let address = "ws://127.0.0.1:\(port)/chat/\(UUID().uuidString)"
            let url = try #require(URL(string: address))
            let before = Date()
            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()
            defer { task.cancel(with: .normalClosure, reason: nil) }

            try await task.send(.string("hello"))
            let echoed = try await task.receive()
            let after = Date()

            let id = try #require(NetworkWebSocketInterception.connectionID(of: task))
            let actual = try #require(NetworkWebSocketRecorder.shared.connections.first { $0.id == id })
            #expect(actual.url == address)
            #expect(actual.isOpen)
            #expect(actual.opened >= before && actual.opened <= after)
            try #require(actual.frames.count == 2)
            let received = actual.frames[0]
            let sent = actual.frames[1]
            #expect(sent.direction == .sent)
            #expect(sent.kind == .text)
            #expect(sent.text == "hello")
            #expect(sent.size == 5)
            #expect(received.direction == .received)
            #expect(received.kind == .text)
            #expect(received.text == "hello")
            #expect(actual.opened <= sent.timestamp)
            #expect(sent.timestamp <= received.timestamp)
            #expect(received.timestamp <= after)
            guard case let .string(text) = echoed else {
                Issue.record("Expected text back, got \(echoed)")
                return
            }
            #expect(text == "hello")
        }

        @Test("A binary frame sent and received through the completion handlers is listed with its size and a hex preview")
        func binaryEchoWithCompletionHandlers() async throws {
            await MainActor.run { NetworkWebSocketInterception.install() }
            let server = try WebSocketEchoServer()
            defer { server.stop() }
            let port = try await server.start()
            let url = try #require(URL(string: "ws://127.0.0.1:\(port)/binary/\(UUID().uuidString)"))
            let session = URLSession(configuration: .ephemeral)
            let task = session.webSocketTask(with: url)
            task.resume()
            defer { task.cancel(with: .normalClosure, reason: nil) }
            let payload = Data(0 ..< 20)

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                task.send(.data(payload)) { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }
            let echoed = try await withCheckedThrowingContinuation { continuation in
                task.receive { continuation.resume(with: $0) }
            }

            let id = try #require(NetworkWebSocketInterception.connectionID(of: task))
            let actual = try #require(NetworkWebSocketRecorder.shared.connections.first { $0.id == id })
            let expectedPreview = "00 01 02 03 04 05 06 07 08 09 0a 0b 0c 0d 0e 0f …"
            #expect(actual.frames.map(\.direction) == [.received, .sent])
            #expect(actual.frames.map(\.kind) == [.binary, .binary])
            #expect(actual.frames.map(\.size) == [20, 20])
            #expect(actual.frames.map(\.hexPreview) == [expectedPreview, expectedPreview])
            #expect(actual.frames.map(\.kindLabel) == ["Binary · 20 B", "Binary · 20 B"])
            guard case let .data(data) = echoed else {
                Issue.record("Expected binary back, got \(echoed)")
                return
            }
            #expect(data == payload)
        }

        @Test("A close the server sends is recorded with its code and reason, and the app's receive still fails as it would")
        func serverClose() async throws {
            await MainActor.run { NetworkWebSocketInterception.install() }
            let server = try WebSocketEchoServer()
            defer { server.stop() }
            let port = try await server.start()
            let url = try #require(URL(string: "ws://127.0.0.1:\(port)/close/\(UUID().uuidString)"))
            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()

            try await task.send(.string("close 4000 bye"))
            let failure = await #expect(throws: (any Error).self) {
                try await task.receive()
            }

            let id = try #require(NetworkWebSocketInterception.connectionID(of: task))
            let actual = try #require(NetworkWebSocketRecorder.shared.connections.first { $0.id == id })
            guard case let .closed(close) = actual.state else {
                Issue.record("Expected the connection closed, got \(actual.state)")
                return
            }
            #expect(close.side == .server)
            #expect(close.code == 4000)
            #expect(close.reason == "bye")
            #expect(close.codeLabel == "4000")
            #expect(task.closeCode.rawValue == 4000)
            #expect(failure != nil)
        }

        @Test("The app's cancel(with:reason:) is recorded with its code and reason, and the receive it cancels doesn't change it")
        func clientCancel() async throws {
            await MainActor.run { NetworkWebSocketInterception.install() }
            let server = try WebSocketEchoServer()
            defer { server.stop() }
            let port = try await server.start()
            let url = try #require(URL(string: "ws://127.0.0.1:\(port)/cancel/\(UUID().uuidString)"))
            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()
            try await task.send(.string("ping me"))
            _ = try await task.receive()

            task.cancel(with: .goingAway, reason: Data("done".utf8))
            let cancelled = await #expect(throws: URLError.self) {
                try await task.receive()
            }

            let id = try #require(NetworkWebSocketInterception.connectionID(of: task))
            let actual = try #require(NetworkWebSocketRecorder.shared.connections.first { $0.id == id })
            guard case let .closed(close) = actual.state else {
                Issue.record("Expected the connection closed, got \(actual.state)")
                return
            }
            #expect(close.side == .app)
            #expect(close.code == 1001)
            #expect(close.reason == "done")
            #expect(close.codeLabel == "1001 Going away")
            #expect(cancelled?.code == .cancelled)
        }

        @Test("A connection the server drops without a close is recorded as failed, with the receive's error")
        func receiveError() async throws {
            await MainActor.run { NetworkWebSocketInterception.install() }
            let server = try WebSocketEchoServer()
            defer { server.stop() }
            let port = try await server.start()
            let url = try #require(URL(string: "ws://127.0.0.1:\(port)/drop/\(UUID().uuidString)"))
            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()
            defer { task.cancel() }

            try await task.send(.string("drop"))
            let failure = await #expect(throws: (any Error).self) {
                try await task.receive()
            }

            let id = try #require(NetworkWebSocketInterception.connectionID(of: task))
            let actual = try #require(NetworkWebSocketRecorder.shared.connections.first { $0.id == id })
            let expectedMessage = try #require(failure).localizedDescription
            guard case let .failed(message, _) = actual.state else {
                Issue.record("Expected the connection failed, got \(actual.state)")
                return
            }
            #expect(message == expectedMessage)
            #expect(actual.isFailure)
            #expect(actual.frames.map(\.text) == ["drop"])
        }

        @Test("A ping is recorded as sent, and its pong as received")
        func pingAndPong() async throws {
            await MainActor.run { NetworkWebSocketInterception.install() }
            let server = try WebSocketEchoServer()
            defer { server.stop() }
            let port = try await server.start()
            let url = try #require(URL(string: "ws://127.0.0.1:\(port)/ping/\(UUID().uuidString)"))
            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()
            defer { task.cancel(with: .normalClosure, reason: nil) }

            // A receive stays pending through the ping (the cancel ends it): URLSession reads the
            // socket only for a pending receive, so without one the pong can go unread and the
            // ping's handler never run.
            task.receive { _ in }
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                task.sendPing { error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                }
            }

            let id = try #require(NetworkWebSocketInterception.connectionID(of: task))
            let actual = try #require(NetworkWebSocketRecorder.shared.connections.first { $0.id == id })
            #expect(actual.frames.map(\.kind) == [.pong, .ping])
            #expect(actual.frames.map(\.direction) == [.received, .sent])
            #expect(actual.frames.map(\.size) == [0, 0])
        }

        @Test("Every factory records one connection per task, with the subprotocols the app offered")
        @MainActor
        func factories() throws {
            NetworkWebSocketInterception.install()
            let url = try #require(URL(string: "ws://127.0.0.1:9/factories/\(UUID().uuidString)"))
            var request = URLRequest(url: url)
            request.setValue("chat, superchat", forHTTPHeaderField: "Sec-WebSocket-Protocol")
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }

            let tasks = [
                session.webSocketTask(with: url),
                session.webSocketTask(with: url, protocols: ["chat", "superchat"]),
                session.webSocketTask(with: request)
            ]

            let ids = try tasks.map { try #require(NetworkWebSocketInterception.connectionID(of: $0)) }
            let connections = NetworkWebSocketRecorder.shared.connections
            let actual = ids.map { id in connections.filter { $0.id == id } }
            #expect(Set(ids).count == 3)
            #expect(actual.map(\.count) == [1, 1, 1])
            #expect(actual.map { $0.first?.url } == Array(repeating: url.absoluteString, count: 3))
            #expect(actual.map { $0.first?.protocols ?? [] } == [[], ["chat", "superchat"], ["chat", "superchat"]])
        }

        @Test("A send after the connection is gone is recorded failed, and the app gets the same error")
        func sendError() async throws {
            await MainActor.run { NetworkWebSocketInterception.install() }
            let server = try WebSocketEchoServer()
            defer { server.stop() }
            let port = try await server.start()
            let url = try #require(URL(string: "ws://127.0.0.1:\(port)/late/\(UUID().uuidString)"))
            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()
            try await task.send(.string("hello"))
            _ = try await task.receive()
            task.cancel(with: .normalClosure, reason: nil)

            let failure = await #expect(throws: (any Error).self) {
                try await task.send(.string("too late"))
            }

            let id = try #require(NetworkWebSocketInterception.connectionID(of: task))
            let actual = try #require(NetworkWebSocketRecorder.shared.connections.first { $0.id == id })
            let late = try #require(actual.frames.first)
            #expect(late.text == "too late")
            #expect(late.failure == failure?.localizedDescription)
        }

        @Test("The plugin's URL protocol leaves a WebSocket's handshake to its task, and still takes an HTTP request")
        func protocolLeavesHandshake() throws {
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let socket = try #require(URL(string: "ws://127.0.0.1:9/handshake"))
            let page = try #require(URL(string: "http://127.0.0.1:9/page"))

            let webSocket = DebugNetworkProtocol.canInit(with: session.webSocketTask(with: socket))
            let data = DebugNetworkProtocol.canInit(with: session.dataTask(with: page))

            #expect(!webSocket)
            #expect(data)
        }

        @Test("The plugin's store shows a connection once its frames are recorded")
        @MainActor
        func storeShowsConnection() async throws {
            await MainActor.run { NetworkWebSocketInterception.install() }
            let server = try WebSocketEchoServer()
            defer { server.stop() }
            let port = try await server.start()
            let address = "ws://127.0.0.1:\(port)/store/\(UUID().uuidString)"
            let url = try #require(URL(string: address))
            let task = URLSession.shared.webSocketTask(with: url)
            task.resume()
            defer { task.cancel(with: .normalClosure, reason: nil) }
            let shown = NetworkStore.shared.$webSockets.values

            try await task.send(.string("hello"))
            _ = try await task.receive()

            var actual: NetworkWebSocketConnection?
            for await connections in shown {
                if let match = connections.first(where: { $0.url == address && $0.frameCount == 2 }) {
                    actual = match
                    break
                }
            }
            #expect(actual?.frames.map(\.direction) == [.received, .sent])
        }
    }
#endif
