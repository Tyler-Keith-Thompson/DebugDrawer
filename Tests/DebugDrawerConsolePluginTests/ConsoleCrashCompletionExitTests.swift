// Exit tests start a child process, which only the Mac's test runs can do. Installing the console
// redirects the process's stdout and stderr and sets the shared store, so it happens only in a
// child.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import os
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleCrashCompletionExitTests {
        @Test("An os_log line logged just before the app crashes is under Previous in the next launch's store")
        @MainActor func lineBeforeCrash() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let expected = "Crashing now \(UUID().uuidString)"

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
            // and while the Mac is busy a read of the system's log can miss a line an earlier read
            // returned (a quarter of reads under a full build and test run). So the next launch
            // here reads the system's log the console's way, again until it holds the line, for
            // at most 30 seconds. Each read blocks on the daemon, so the loop waits on it, not on
            // a clock. Under that load the child took up to 2.8 seconds and a read up to 6.3; the
            // next launch's read, at utility then, took 29 and 34 seconds, which ran the suite
            // past its minute.
            let reading = RetryingSystemLog(expected: expected, deadline: .now.advanced(by: .seconds(30)))
            let next = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: _ConsoleSessionStorage(directory: directory)), systemLog: reading
            )
            let sut = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            sut.persist(to: next)
            let sessions = ConsoleSessionsModel(recorder: next)
            await sessions.reload()
            let reads = reading.reads.withLock(\.self)
            try #require(reads.holdsLine, "The system's log didn't hold the child's line after \(reads.count) reads in 30 seconds")
            let session = try #require(sessions.sessions.first)
            let log = try #require(await sessions.log(of: session.id))
            await sut.showPrevious(log)
            let actual = sut.shownLines.filter { $0.text == expected }

            #expect(actual.map(\.source) == [.oslog])
            #expect(actual.map(\.subsystem) == ["DebugDrawerConsolePluginTests"])
            #expect(actual.map(\.category) == ["Crash"])
            #expect(actual.map(\.level) == [.notice])
        }
    }

    /// The system's log read as the console reads it, again until the lines hold `expected` or
    /// `deadline` passes.
    private struct RetryingSystemLog: ConsoleSystemLog {
        let expected: String
        let deadline: ContinuousClock.Instant
        /// How many reads were made, and whether the last one held `expected`. Behind a lock, as
        /// the recorder reads on a dispatch queue and the test checks it on the main actor.
        let reads = OSAllocatedUnfairLock(initialState: (count: 0, holdsLine: false))

        func lines(loggedBy processIdentifier: Int32, since date: Date) -> ConsoleEarlierProcess {
            var outcome = ConsoleEarlierProcess.running
            var holdsLine = false
            repeat {
                outcome = _ConsoleSystemLog().lines(loggedBy: processIdentifier, since: date)
                if case let .ended(lines) = outcome { holdsLine = lines.contains { $0.text == expected } }
                reads.withLock { [holdsLine] in $0 = (count: $0.count + 1, holdsLine: holdsLine) }
            } while !holdsLine && ContinuousClock.now < deadline
            return outcome
        }
    }
#endif
