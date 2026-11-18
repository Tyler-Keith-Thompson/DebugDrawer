#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    // Each recorder made over a storage is a launch of the app; the launch before's process is
    // 4242, and a fake system log answers for it. Listing the earlier sessions waits until the
    // launch has completed the one before, so a test awaits it before it looks at the storage.
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleSessionCompletionTests {
        @Test("A launch adds to the session before it the os_log lines its process logged after the session's last one")
        @MainActor func addsMissedLines() async throws {
            let storage = FakeConsoleSessionStorage()
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let earlier = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: storage), started: started, processIdentifier: 4242)
            earlier.record(LogLine(timestamp: started.addingTimeInterval(1), text: "Feed loaded", source: .oslog, level: .info))
            earlier.record(LogLine(timestamp: started.addingTimeInterval(2), text: "Tapped Buy", source: .stdout, level: .debug))
            _ = await earlier.previousSessions()
            let systemLog = FakeConsoleSystemLog(.ended([
                LogLine(timestamp: started.addingTimeInterval(1), text: "Feed loaded", source: .oslog, level: .info),
                LogLine(
                    timestamp: started.addingTimeInterval(3), text: "Checkout failed", source: .oslog, level: .error,
                    subsystem: "com.example.shop", category: "Checkout"
                )
            ]))
            let expectedReads = [FakeConsoleSystemLog.Read(processIdentifier: 4242, since: started.addingTimeInterval(1).addingTimeInterval(-0.001))]

            let sut = ConsoleSessionsModel(recorder: ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: started.addingTimeInterval(60), systemLog: systemLog
            ))
            await sut.reload()
            let session = try #require(sut.sessions.first)
            let actual = try #require(await sut.log(of: session.id)).lines

            #expect(sut.sessions.map(\.id) == [earlier.currentName])
            #expect(actual.map(\.text) == ["Feed loaded", "Tapped Buy", "Checkout failed"])
            #expect(actual.map(\.source) == [.oslog, .stdout, .oslog])
            #expect(actual.last?.level == .error)
            #expect(actual.last?.subsystem == "com.example.shop")
            #expect(actual.last?.category == "Checkout")
            #expect(systemLog.reads == expectedReads)
        }

        @Test("A line in the same millisecond as the session's last os_log line is added when its text differs")
        func sameMillisecond() async throws {
            let storage = FakeConsoleSessionStorage()
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let earlier = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: storage), started: started, processIdentifier: 4242)
            earlier.record(LogLine(timestamp: started.addingTimeInterval(1), text: "Feed loaded", source: .oslog, level: .info))
            _ = await earlier.previousSessions()
            let systemLog = FakeConsoleSystemLog(.ended([
                LogLine(timestamp: started.addingTimeInterval(1.0002), text: "Feed loaded", source: .oslog, level: .info),
                LogLine(timestamp: started.addingTimeInterval(1.0004), text: "Feed shown", source: .oslog, level: .info)
            ]))

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: started.addingTimeInterval(60), systemLog: systemLog
            )
            let session = try #require(await sut.previousSessions().first)
            let actual = try await sut.log(of: session).lines.map(\.text)

            #expect(actual == ["Feed loaded", "Feed shown"])
        }

        @Test("The system's log is read from the session's start when the session kept no os_log line")
        func readsFromStart() async throws {
            let storage = FakeConsoleSessionStorage()
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let earlier = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: storage), started: started, processIdentifier: 4242)
            earlier.record(LogLine(timestamp: started.addingTimeInterval(1), text: "Tapped Buy", source: .stdout, level: .debug))
            _ = await earlier.previousSessions()
            let systemLog = FakeConsoleSystemLog(.ended([]))
            let expected = [FakeConsoleSystemLog.Read(processIdentifier: 4242, since: started.addingTimeInterval(-0.001))]

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: started.addingTimeInterval(60), systemLog: systemLog
            )
            _ = await sut.previousSessions()

            #expect(systemLog.reads == expected)
        }

        @Test("Lines the console's ingest filter drops aren't added")
        func ingestFilter() async throws {
            let storage = FakeConsoleSessionStorage()
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let earlier = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: storage), started: started, processIdentifier: 4242)
            _ = await earlier.previousSessions()
            let systemLog = FakeConsoleSystemLog(.ended([
                LogLine(
                    timestamp: started.addingTimeInterval(1), text: "Event dispatched", source: .oslog, level: .debug, subsystem: "com.apple.UIKit"
                ),
                LogLine(
                    timestamp: started.addingTimeInterval(2), text: "Checkout failed", source: .oslog, level: .error, subsystem: "com.example.shop"
                )
            ]))

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: started.addingTimeInterval(60), systemLog: systemLog
            )
            let session = try #require(await sut.previousSessions().first)
            let actual = try await sut.log(of: session).lines.map(\.text)

            #expect(actual == ["Checkout failed"])
        }

        @Test("A session that kept no line, and whose process logged none it missed, is deleted")
        func deletesEmptySession() async {
            let storage = FakeConsoleSessionStorage()
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let earlier = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: storage), started: started, processIdentifier: 4242)
            _ = await earlier.previousSessions()

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: started.addingTimeInterval(60), systemLog: FakeConsoleSystemLog(.ended([]))
            )
            let actual = await sut.previousSessions()

            #expect(actual.isEmpty)
            #expect(storage.sessions.keys.sorted() == [sut.currentName])
        }

        @Test("A session whose process still runs is left as it is")
        func processRunning() async throws {
            let storage = FakeConsoleSessionStorage()
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let earlier = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: storage), started: started, processIdentifier: 4242)
            _ = await earlier.previousSessions()
            let expected = try #require(storage.sessions[earlier.currentName])

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: started.addingTimeInterval(60), systemLog: FakeConsoleSystemLog(.running)
            )
            let listed = await sut.previousSessions().map(\.id)
            let actual = storage.sessions[earlier.currentName]

            #expect(listed == [earlier.currentName])
            #expect(actual == expected)
        }

        @Test("A session whose header doesn't name its process isn't completed")
        func noProcessIdentifier() async throws {
            let name = ConsoleSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID())
            let file = Data("""
            {"app":"Shop","appVersion":"2.1 (40)","debugDrawerConsoleSession":1,"started":"2027-01-15T08:00:00.000Z"}
            {"level":"info","source":"oslog","text":"Feed loaded","time":"2027-01-15T08:00:01.000Z"}

            """.utf8)
            let storage = FakeConsoleSessionStorage(sessions: [name: file])
            let systemLog = FakeConsoleSystemLog(.ended([
                LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_002), text: "Checkout failed", source: .oslog, level: .error)
            ]))

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_060), systemLog: systemLog
            )
            _ = await sut.previousSessions()
            let actual = storage.sessions[name]

            #expect(actual == file)
            #expect(systemLog.reads.isEmpty)
        }

        @Test("A launch writes its session's header, naming its process, before it records a line")
        func headerAtLaunch() throws {
            let storage = FakeConsoleSessionStorage()

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_000), processIdentifier: 4242,
                systemLog: FakeConsoleSystemLog(.ended([]))
            )
            let data = try #require(storage.sessions[sut.currentName])
            let actual = try JSONDecoder().decode(ConsoleSessionHeader.self, from: data)

            #expect(actual.processIdentifier == 4242)
            #expect(actual.started == "2027-01-15T08:00:00.000Z")
            #expect(data.last == UInt8(ascii: "\n"))
        }
    }
#endif
