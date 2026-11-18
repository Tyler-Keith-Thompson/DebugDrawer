// Installing registers the URL protocol, swizzles every session configuration and sets the
// process's body limit, so these run in child processes, in a file of their own, as exit tests
// need one.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite("installNetwork(bodyLimit:), in a child process", .timeLimit(.minutes(1)))
    struct NetworkBodyLimitExitTests {
        @Test("A response larger than the limit reaches the app whole; the log keeps its first bytes, marked truncated, with its full size")
        func capsCapturedBody() async {
            await #expect(processExitsWith: .success) {
                await MainActor.run {
                    DebugDrawer.shared.installNetwork(sessions: .off, bodyLimit: 4)
                }
                // The server answers `{"ok":true}`, 11 bytes.
                guard let server = try? RecordingServer(), let port = try? await server.start(),
                      let url = URL(string: "http://127.0.0.1:\(port)/v1/limit"),
                      let (received, _) = try? await URLSession(configuration: .ephemeral).data(from: url)
                else { exit(EXIT_FAILURE) }
                let captured = await Task { @MainActor () -> NetworkEntry? in
                    for await entries in NetworkStore.shared.$entries.values {
                        if let entry = entries.first(where: { $0.url == url.absoluteString && $0.isComplete }) {
                            return entry
                        }
                    }
                    return nil
                }.value
                server.stop()
                guard let captured else { exit(EXIT_FAILURE) }
                let isExpected = received == Data(#"{"ok":true}"#.utf8)
                    && captured.responseBody == Data(#"{"ok"#.utf8)
                    && captured.responseBodySize == 11
                    && captured.isResponseBodyTruncated
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("A negative body limit traps")
        func negativeLimitTraps() async {
            await #expect(processExitsWith: .failure) {
                await MainActor.run {
                    DebugDrawer.shared.installNetwork(sessions: .off, bodyLimit: -1)
                }
            }
        }
    }
#endif
