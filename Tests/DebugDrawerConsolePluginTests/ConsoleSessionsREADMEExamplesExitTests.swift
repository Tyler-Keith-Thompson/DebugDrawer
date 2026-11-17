// The README's Console sessions example, verbatim, so the README cannot drift from the code. It
// runs in a child process, as installing redirects stdout and stderr and polls the unified log of
// the process that runs it. It is in a file of its own, as exit tests need one, and lives here
// rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    @Suite("README examples, in a child process: Console sessions", .timeLimit(.minutes(1)))
    struct ConsoleSessionsREADMEExamplesExitTests {
        @Test("Console sessions: the installed limits apply, and a line is written to the current session as it is captured")
        func consoleSessions() async {
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: home) }

            await #expect(processExitsWith: .success) { [home = home.path(percentEncoded: false) as String] in
                // The child's home is a temporary directory, so the default storage, in Application
                // Support, is in it rather than the Mac's own. Nothing is installed unless it is.
                setenv("CFFIXED_USER_HOME", home, 1)
                guard _ConsoleSessionStorage.defaultDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                await MainActor.run {
                    DebugDrawer.shared.installConsole(sessions: ConsoleSessionPersistence(maxSessions: 3, maxBytes: 5_000_000))
                }
                let recorder = await MainActor.run { () -> ConsoleSessionRecorder? in
                    ConsoleLogStore.shared.ingest(LogLine(timestamp: Date(), text: "README example line", source: .oslog, level: .info))
                    return ConsoleLogStore.shared.recorder
                }
                guard let recorder else { exit(EXIT_FAILURE) }
                _ = await recorder.previousSessions()
                let written = (try? recorder.persistence.storage.contents(ofSessionNamed: recorder.currentName)) ?? Data()
                let isWritten = (String(bytes: written, encoding: .utf8) ?? "").contains("README example line")
                let isExpected = recorder.persistence.maxSessions == 3 && recorder.persistence.maxBytes == 5_000_000 && isWritten
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
