// The README's Network sessions example, verbatim, so the README cannot drift from the code. It
// runs in a child process, as installing registers the URL protocol and swizzles every session
// configuration in the process that runs it. It is in a file of its own, as exit tests need one,
// and lives here rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite("README examples, in a child process: Network sessions", .timeLimit(.minutes(1)))
    struct NetworkSessionsREADMEExamplesExitTests {
        @Test("Network sessions: the installed limits apply, and a request is written to the current session as it completes")
        func networkSessions() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                await MainActor.run {
                    DebugDrawer.shared.installNetwork(sessions: NetworkSessionPersistence(maxSessions: 3, maxBytes: 5_000_000))
                }
                // `.invalid` never resolves, so the request fails at once, with or without a
                // network, and is written as a failure.
                guard let url = URL(string: "https://sessions.invalid/v1/ping") else { exit(EXIT_FAILURE) }
                _ = try? await URLSession.shared.data(from: url)
                let recorder = await Task { @MainActor in
                    for await entries in NetworkStore.shared.$entries.values where entries.first?.isComplete == true {
                        break
                    }
                    return NetworkStore.shared.recorder
                }.value
                guard let recorder else { exit(EXIT_FAILURE) }
                _ = await recorder.previousSessions()
                // The session is in Application Support, in the child's temporary home folder
                // (CFFIXED_USER_HOME above).
                let written = (try? recorder.persistence.storage.contents(ofSessionNamed: recorder.currentName)) ?? Data()
                let isWritten = (String(bytes: written, encoding: .utf8) ?? "").contains("https://sessions.invalid/v1/ping")
                let isExpected = recorder.persistence.maxSessions == 3 && recorder.persistence.maxBytes == 5_000_000
                    && isWritten
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
