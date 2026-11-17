// Exit tests start a child process, which only the Mac's test runs can do.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleSessionExitTests {
        @Test("A negative session count traps")
        func negativeSessions() async {
            await #expect(processExitsWith: .failure) {
                _ = ConsoleSessionPersistence(maxSessions: -1)
            }
        }

        @Test("A size limit of 0 traps")
        func zeroBytes() async {
            await #expect(processExitsWith: .failure) {
                _ = ConsoleSessionPersistence(maxBytes: 0)
            }
        }

        @Test("Lines written before the app crashes are listed as the previous session by the next launch")
        func survivesCrash() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }

            await #expect(processExitsWith: .signal(SIGABRT)) { [path = directory.path(percentEncoded: false) as String] in
                let storage = _ConsoleSessionStorage(directory: URL(filePath: path, directoryHint: .isDirectory))
                let recorder = ConsoleSessionRecorder(
                    ConsoleSessionPersistence(storage: storage),
                    started: Date(timeIntervalSince1970: 1_800_000_000)
                )
                for index in 1 ... 3 {
                    recorder.record(LogLine(
                        timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), text: "line \(index)", source: .oslog, level: .info
                    ))
                }
                // Written once the queue reaches this; then the app dies without unwinding.
                _ = await recorder.previousSessions()
                abort()
            }
            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: _ConsoleSessionStorage(directory: directory)),
                started: Date(timeIntervalSince1970: 1_800_000_100)
            )
            let session = try #require(await sut.previousSessions().first)
            let actual = try await sut.log(of: session)

            #expect(actual.lines.map(\.text) == ["line 1", "line 2", "line 3"])
        }
    }
#endif
