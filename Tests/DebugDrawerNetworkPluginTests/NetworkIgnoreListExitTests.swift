// Installing registers the URL protocol and swizzles every session configuration in the process
// that runs it, so this runs in a child process, in a file of its own, as exit tests need one.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite("installNetwork(ignoring:), in a child process", .timeLimit(.minutes(1)))
    struct NetworkIgnoreListExitTests {
        @Test("The app's hosts join the ignore list; a request to one is captured but left out of the log's list")
        func seedsHideRequests() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                // Sessions go to a folder of the child's own, so nothing is written to the test
                // runner's Application Support; the seeds aren't written at install.
                let sessions = FileManager.default.temporaryDirectory.appending(path: "NetworkIgnoreListExitTests-\(UUID().uuidString)")
                try await MainActor.run {
                    try DebugDrawer.shared.installNetwork(
                        ignoring: ["analytics.invalid", "not a host"],
                        sessions: try NetworkSessionPersistence(storage: _NetworkSessionStorage(directory: sessions))
                    )
                }
                // `.invalid` never resolves, so the request fails at once, with or without a network.
                guard let url = URL(string: "https://events.analytics.invalid/v1/collect") else { exit(EXIT_FAILURE) }
                _ = try? await URLSession.shared.data(from: url)
                // Waits for this request alone: the child may capture others of its own.
                let (captured, listed, ignored) = await Task { @MainActor in
                    for await entries in NetworkStore.shared.$entries.values
                        where entries.contains(where: { $0.host == "events.analytics.invalid" && $0.isComplete }) {
                        break
                    }
                    let store = NetworkStore.shared
                    return (store.entries.map(\.host), store.filteredEntries.map(\.host), store.ignoredDomains.map(\.name))
                }.value
                try? FileManager.default.removeItem(at: sessions)
                let isExpected = captured.contains("events.analytics.invalid") && !listed.contains("events.analytics.invalid")
                    && listed.count == captured.count - 1 && ignored.contains("analytics.invalid") && !ignored.contains("not a host")
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
