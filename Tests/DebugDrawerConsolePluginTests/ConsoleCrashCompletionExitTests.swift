// Exit tests start a child process, which only the Mac's test runs can do. Installing the console
// redirects the process's stdout and stderr and sets the shared store, so it happens only in a
// child.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import os
    import OSLog
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleCrashCompletionExitTests {
        @Test("An os_log line logged just before the app crashes is under Previous in the next launch's store")
        @MainActor func lineBeforeCrash() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let expected = "Crashing now \(UUID().uuidString)"
            let launched = Date()

            /// Whether the system's log holds the child's line yet.
            func systemLogHoldsLine() throws -> Bool {
                let store = try OSLogStore(scope: .system)
                let predicate = NSPredicate(format: "subsystem == %@", "DebugDrawerConsolePluginTests")
                return try store.getEntries(at: store.position(date: launched), matching: predicate)
                    .contains { ($0 as? OSLogEntryLog)?.composedMessage == expected }
            }

            // The child crashes as soon as it has logged the line, long before the console's
            // two-second read of its own log could take the line in.
            let path = directory.path(percentEncoded: false)
            await #expect(processExitsWith: .signal(SIGABRT)) { [path = path as String, expected = expected as String] in
                await MainActor.run {
                    let storage = _ConsoleSessionStorage(directory: URL(filePath: path, directoryHint: .isDirectory))
                    DebugDrawer.shared.installConsole(sessions: ConsoleSessionPersistence(storage: storage))
                }
                os.Logger(subsystem: "DebugDrawerConsolePluginTests", category: "Crash").notice("\(expected, privacy: .public)")
                abort()
            }
            // The log daemon takes in a crashed process's last lines after the process is gone,
            // under load later than this test would start its next launch; a launch that starts
            // before then misses them. So the next launch here starts once the system's log holds
            // the line. Each read blocks on the daemon, so the loop waits on it, not on a clock.
            var isLogged = false
            while !isLogged {
                isLogged = try systemLogHoldsLine()
            }
            let next = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: _ConsoleSessionStorage(directory: directory)))
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            sut.persist(to: next)
            let sessions = ConsoleSessionsModel(recorder: next)
            await sessions.reload()
            let session = try #require(sessions.sessions.first)
            let log = try #require(await sessions.log(of: session.id))
            sut.showPrevious(log)
            let actual = sut.shownLines.filter { $0.text == expected }

            #expect(actual.map(\.source) == [.oslog])
            #expect(actual.map(\.subsystem) == ["DebugDrawerConsolePluginTests"])
            #expect(actual.map(\.category) == ["Crash"])
            #expect(actual.map(\.level) == [.notice])
        }
    }
#endif
