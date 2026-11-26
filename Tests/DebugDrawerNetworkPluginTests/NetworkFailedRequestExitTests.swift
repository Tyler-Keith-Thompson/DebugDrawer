// Installing registers the URL protocol and swizzles every session configuration in the process
// that runs it, so this runs in a child process, in a file of its own, as exit tests need one.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite("Failed requests through installNetwork(), in a child process", .timeLimit(.minutes(1)))
    struct NetworkFailedRequestExitTests {
        @Test("""
        Installed by installNetwork(), URLSession.shared requests that fail (a host that never resolves, a 404) are in the model's \
        snapshot under All, Errors and, for the 404, 4xx, and still there once the snapshot is encoded and decoded for a viewer
        """)
        func failedRequestsInSnapshot() async {
            // The child gets a home folder of its own, so the files it keeps in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; it checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }

                /// Sends a GET to `address` on the shared session, as an app does, and returns the error it
                /// failed with, if any.
                func send(to address: String) async throws -> URLError? {
                    let url = try #require(URL(string: address))
                    do {
                        _ = try await URLSession.shared.data(from: url)
                        return nil
                    } catch let error as URLError {
                        return error
                    }
                }

                @MainActor
                func waitUntilLogged(_ addresses: Set<String>) async {
                    for await entries in NetworkStore.shared.$entries.values
                        where addresses.isSubset(of: Set(entries.filter(\.isComplete).map(\.url))) {
                        break
                    }
                }

                @MainActor
                func urls(under filter: NetworkStore.StatusFilter, in model: NetworkModel) -> Set<String> {
                    model.perform(NetworkCommand(.log(.setFilterStatus(filter))))
                    return Set(model.snapshot.log.filteredEntries.map(\.url))
                }

                @MainActor
                func check() async throws {
                    let server = try ScriptedServer { _ in
                        "HTTP/1.1 404 Not Found\r\nContent-Type: text/plain\r\nContent-Length: 9\r\nConnection: close\r\n\r\nnot found"
                    }
                    defer { server.stop() }
                    let port = try await server.start()
                    try DebugDrawer.shared.installNetwork(sessions: .off)
                    let model = NetworkModel.shared
                    // `.invalid` never resolves (RFC 6761), and no rule or condition answers it.
                    let unresolvable = "https://nowhere.invalid/\(UUID().uuidString)"
                    let notFound = "http://127.0.0.1:\(port)/missing/\(UUID().uuidString)"
                    let expected: Set = [unresolvable, notFound]

                    let thrown = try await send(to: unresolvable)
                    _ = try await send(to: notFound)
                    await waitUntilLogged(expected)

                    let all = urls(under: .all, in: model)
                    let errors = urls(under: .errors, in: model)
                    let clientErrors = urls(under: .clientError, in: model)
                    let success = urls(under: .success, in: model)
                    model.perform(NetworkCommand(.log(.setFilterStatus(.all))))
                    let decoded = try JSONDecoder().decode(NetworkSnapshot.self, from: JSONEncoder().encode(model.snapshot))
                    let unresolvableEntry = model.snapshot.log.captured.first { $0.url == unresolvable }
                    #expect(all == expected)
                    #expect(errors == expected)
                    #expect(clientErrors == [notFound])
                    #expect(success.isEmpty)
                    #expect(Set(decoded.log.filteredEntries.map(\.url)) == expected)
                    #expect(thrown?.code == .cannotFindHost)
                    #expect(unresolvableEntry?.statusCode == nil)
                    #expect(unresolvableEntry?.error == thrown?.localizedDescription)
                }
                try await check()
            }
        }
    }
#endif
