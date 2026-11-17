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
            await #expect(processExitsWith: .success) {
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
                // The session is in the test runner's folder of Application Support, beside other
                // children's, so only this one is removed. Bazel's sandbox doesn't let a test write
                // there, so the write is checked only where the folder can be made, as under
                // SwiftPM; the recorder's own tests check writing in a folder of their own.
                let canWrite = (try? FileManager.default.createDirectory(
                    at: _NetworkSessionStorage.defaultDirectory, withIntermediateDirectories: true
                )) != nil
                let written = (try? recorder.persistence.storage.contents(ofSessionNamed: recorder.currentName)) ?? Data()
                try? recorder.persistence.storage.deleteSession(named: recorder.currentName)
                let isWritten = (String(bytes: written, encoding: .utf8) ?? "").contains("https://sessions.invalid/v1/ping")
                let isExpected = recorder.persistence.maxSessions == 3 && recorder.persistence.maxBytes == 5_000_000
                    && (isWritten || !canWrite)
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
