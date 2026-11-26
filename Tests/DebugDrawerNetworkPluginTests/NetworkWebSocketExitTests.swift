// What installing changes, and what it must not, pinned in child processes: the interception
// replaces methods for the rest of the process it runs in, so only a process that has not run it
// shows what the app gets without the plugin. Each child installs the whole plugin, whose URL
// protocol must leave the WebSocket handshake alone. It is in a file of its own, as exit tests
// need one.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite("WebSocket interception, in a child process", .timeLimit(.minutes(1)))
    struct NetworkWebSocketExitTests {
        @Test("Nothing is recorded until installNetwork() runs; after it, the same traffic is")
        func notInterceptedUntilInstalled() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                func talk(to url: URL) async throws -> URLSessionWebSocketTask {
                    let task = URLSession.shared.webSocketTask(with: url)
                    task.resume()
                    try await task.send(.string("hello"))
                    _ = try await task.receive()
                    // A receive stays pending through the ping (the cancel below ends it):
                    // URLSession reads the socket only for a pending receive, so without one the
                    // pong can go unread and the ping's handler never run.
                    task.receive { _ in }
                    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                        task.sendPing { error in
                            if let error { continuation.resume(throwing: error) } else { continuation.resume() }
                        }
                    }
                    task.cancel(with: .normalClosure, reason: nil)
                    return task
                }

                let server = try? WebSocketEchoServer()
                guard let server, let port = try? await server.start(),
                      let url = URL(string: "ws://127.0.0.1:\(port)/echo")
                else { exit(EXIT_FAILURE) }

                guard let before = try? await talk(to: url) else { exit(EXIT_FAILURE) }
                let recordedBefore = NetworkWebSocketRecorder.shared.connections.count
                let idBefore = NetworkWebSocketInterception.connectionID(of: before)

                try await MainActor.run { try DebugDrawer.shared.installNetwork() }
                guard let after = try? await talk(to: url) else { exit(EXIT_FAILURE) }
                let recordedAfter = NetworkWebSocketRecorder.shared.connections
                let idAfter = NetworkWebSocketInterception.connectionID(of: after)

                let isExpected = recordedBefore == 0 && idBefore == nil
                    && recordedAfter.count == 1 && idAfter == recordedAfter.first?.id && recordedAfter.first?.frameCount == 4
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("The app gets the same messages, errors and close codes with the plugin installed as without it")
        func hostSeesTheSame() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                /// What the app sees, as text: each message or error its sends, receives and pings
                /// get, through the async and the completion-handler APIs, and the close codes and
                /// reasons the tasks report after the server's close and the app's.
                func session(on port: UInt16) async -> [String] {
                    @Sendable func describe(_ result: Result<URLSessionWebSocketTask.Message, any Error>) -> String {
                        switch result {
                        case let .success(.string(text)): "text \(text)"
                        case let .success(.data(data)): "data \(data.map { String(format: "%02x", $0) }.joined())"
                        case let .success(message): "message \(message)"
                        case let .failure(error): "error \((error as NSError).domain) \((error as NSError).code)"
                        }
                    }
                    @Sendable func describe(_ error: (any Error)?) -> String {
                        error.map { "error \(($0 as NSError).domain) \(($0 as NSError).code)" } ?? "ok"
                    }
                    guard let echo = URL(string: "ws://127.0.0.1:\(port)/parity"),
                          let cancelled = URL(string: "ws://127.0.0.1:\(port)/parity-cancel")
                    else { return ["no URL"] }
                    var seen: [String] = []

                    let task = URLSession.shared.webSocketTask(with: echo)
                    task.resume()
                    do { try await task.send(.string("hello")); seen.append("sent ok") } catch { seen.append(describe(error)) }
                    do { seen.append(describe(.success(try await task.receive()))) } catch { seen.append(describe(.failure(error))) }
                    let sent = await withCheckedContinuation { continuation in
                        task.send(.data(Data([0xDE, 0xAD, 0xBE, 0xEF]))) { continuation.resume(returning: describe($0)) }
                    }
                    seen.append("sent \(sent)")
                    seen.append(await withCheckedContinuation { continuation in
                        task.receive { continuation.resume(returning: describe($0)) }
                    })
                    // The receive that gets the server's close is pending through the ping:
                    // URLSession reads the socket only for a pending receive, so without one the
                    // pong can go unread and the ping's handler never run.
                    let (closeReceived, closeReceivedContinuation) = AsyncStream.makeStream(of: String.self)
                    task.receive { result in
                        closeReceivedContinuation.yield(describe(result))
                        closeReceivedContinuation.finish()
                    }
                    seen.append(await withCheckedContinuation { continuation in
                        task.sendPing { continuation.resume(returning: "pong \(describe($0))") }
                    })
                    do { try await task.send(.string("close 4000 bye")); seen.append("sent ok") } catch { seen.append(describe(error)) }
                    for await received in closeReceived {
                        seen.append(received)
                    }
                    seen.append("close \(task.closeCode.rawValue) \(task.closeReason.flatMap { String(bytes: $0, encoding: .utf8) } ?? "none")")

                    let other = URLSession.shared.webSocketTask(with: cancelled)
                    other.resume()
                    do { try await other.send(.string("first")); seen.append("sent ok") } catch { seen.append(describe(error)) }
                    do { seen.append(describe(.success(try await other.receive()))) } catch { seen.append(describe(.failure(error))) }
                    other.cancel(with: .goingAway, reason: Data("done".utf8))
                    do { seen.append(describe(.success(try await other.receive()))) } catch { seen.append(describe(.failure(error))) }
                    seen.append("close \(other.closeCode.rawValue) \(other.closeReason.flatMap { String(bytes: $0, encoding: .utf8) } ?? "none")")
                    return seen
                }

                let server = try? WebSocketEchoServer()
                guard let server, let port = try? await server.start() else { exit(EXIT_FAILURE) }

                let without = await session(on: port)
                try await MainActor.run { try DebugDrawer.shared.installNetwork() }
                let with = await session(on: port)

                let recorded = NetworkWebSocketRecorder.shared.connections.count
                let expectedStart = ["sent ok", "text hello", "sent ok", "data deadbeef", "pong ok", "sent ok"]
                let isExpected = without == with && Array(with.prefix(6)) == expectedStart && recorded == 2
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
