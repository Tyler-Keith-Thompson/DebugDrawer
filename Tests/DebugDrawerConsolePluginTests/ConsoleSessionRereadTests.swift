#if DEBUG
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    // Under load one read of the system's log can miss a line the store holds, so the next launch
    // reads it again until a read holds the session's own last os_log line and finds nothing the
    // reads before it lacked, at most `ConsoleSystemLogReads.maxReads` times. The launch before's
    // process is 4242; a fake system log answers each read in turn.
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleSessionRereadTests {
        private static let started = Date(timeIntervalSince1970: 1_800_000_000)
        private static let lastKept = LogLine(timestamp: started.addingTimeInterval(1), text: "Feed loaded", source: .oslog, level: .info)
        private static let checkoutFailed = LogLine(
            timestamp: started.addingTimeInterval(3), text: "Checkout failed", source: .oslog, level: .error,
            subsystem: "com.example.shop", category: "Checkout"
        )

        /// An earlier launch's session over `storage` that kept `lines`.
        private static func earlierSession(in storage: FakeConsoleSessionStorage, keeping lines: [LogLine]) async -> ConsoleSessionRecorder {
            let earlier = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: storage), started: started, processIdentifier: 4242)
            for line in lines {
                earlier.record(line)
            }
            _ = await earlier.previousSessions()
            return earlier
        }

        @Test("A line the first read of the system's log drops still ends up in the Previous session")
        @MainActor func firstReadDropsLine() async throws {
            let storage = FakeConsoleSessionStorage()
            let earlier = await Self.earlierSession(in: storage, keeping: [Self.lastKept])
            let systemLog = FakeConsoleSystemLog(reads: [
                .ended([Self.lastKept]),
                .ended([Self.lastKept, Self.checkoutFailed])
            ])

            let sut = ConsoleSessionsModel(recorder: ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: Self.started.addingTimeInterval(60), systemLog: systemLog
            ))
            await sut.reload()
            let session = try #require(sut.sessions.first)
            let actual = try #require(await sut.log(of: session.id)).lines

            #expect(sut.sessions.map(\.id) == [earlier.currentName])
            #expect(actual.map(\.text) == ["Feed loaded", "Checkout failed"])
            #expect(actual.last?.level == .error)
            #expect(actual.last?.subsystem == "com.example.shop")
            // The second read found a line the first lacked, so a third confirmed it.
            #expect(systemLog.reads.count == 3)
        }

        @Test("A launch that logged nothing after its session's last line is read twice, and its session is left as it was")
        func loggedNothingMore() async throws {
            let storage = FakeConsoleSessionStorage()
            let earlier = await Self.earlierSession(in: storage, keeping: [Self.lastKept])
            let expected = try #require(storage.sessions[earlier.currentName])
            let systemLog = FakeConsoleSystemLog(.ended([Self.lastKept]))

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: Self.started.addingTimeInterval(60), systemLog: systemLog
            )
            let listed = await sut.previousSessions().map(\.id)

            #expect(listed == [earlier.currentName])
            #expect(storage.sessions[earlier.currentName] == expected)
            #expect(systemLog.reads.count == 2)
        }

        @Test("Reads that lack the session's own last os_log line don't settle, though they agree")
        func lastLineMissing() async throws {
            let storage = FakeConsoleSessionStorage()
            let earlier = await Self.earlierSession(in: storage, keeping: [Self.lastKept])
            let systemLog = FakeConsoleSystemLog(reads: [
                .ended([]),
                .ended([]),
                .ended([Self.lastKept, Self.checkoutFailed])
            ])

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: Self.started.addingTimeInterval(60), systemLog: systemLog
            )
            let session = try #require(await sut.previousSessions().first)
            let actual = try await sut.log(of: session).lines.map(\.text)

            #expect(session.id == earlier.currentName)
            #expect(actual == ["Feed loaded", "Checkout failed"])
            #expect(systemLog.reads.count == 4)
        }

        @Test("The system's log is read at most four times, though each read finds a line the ones before it lacked")
        func boundedReads() async throws {
            let storage = FakeConsoleSessionStorage()
            _ = await Self.earlierSession(in: storage, keeping: [])
            let lines = (1 ... 6).map {
                LogLine(timestamp: Self.started.addingTimeInterval(Double($0)), text: "Step \($0)", source: .oslog, level: .info)
            }
            let systemLog = FakeConsoleSystemLog(reads: (1 ... 6).map { .ended(Array(lines.prefix($0))) })

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: Self.started.addingTimeInterval(60), systemLog: systemLog
            )
            let session = try #require(await sut.previousSessions().first)
            let actual = try await sut.log(of: session).lines.map(\.text)

            #expect(ConsoleSystemLogReads.maxReads == 4)
            #expect(systemLog.reads.count == 4)
            #expect(actual == ["Step 1", "Step 2", "Step 3", "Step 4"])
        }

        @Test("A process found running on a later read leaves its session as it was")
        func runningOnLaterRead() async throws {
            let storage = FakeConsoleSessionStorage()
            let earlier = await Self.earlierSession(in: storage, keeping: [Self.lastKept])
            let expected = try #require(storage.sessions[earlier.currentName])
            let systemLog = FakeConsoleSystemLog(reads: [.ended([Self.lastKept, Self.checkoutFailed]), .running])

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: Self.started.addingTimeInterval(60), systemLog: systemLog
            )
            _ = await sut.previousSessions()

            #expect(storage.sessions[earlier.currentName] == expected)
            #expect(systemLog.reads.count == 2)
        }

        @Test("A system log that can't be read is read once, and a session that kept no line is deleted as before")
        func unreadable() async {
            let storage = FakeConsoleSessionStorage()
            _ = await Self.earlierSession(in: storage, keeping: [])
            let systemLog = FakeConsoleSystemLog(.unreadable)

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: Self.started.addingTimeInterval(60), systemLog: systemLog
            )
            let actual = await sut.previousSessions()

            #expect(actual.isEmpty)
            #expect(storage.sessions.keys.sorted() == [sut.currentName])
            #expect(systemLog.reads.count == 1)
        }

        @Test("A read that fails after one that found a line still adds that line")
        func unreadableAfterLine() async throws {
            let storage = FakeConsoleSessionStorage()
            _ = await Self.earlierSession(in: storage, keeping: [Self.lastKept])
            let systemLog = FakeConsoleSystemLog(reads: [.ended([Self.lastKept, Self.checkoutFailed]), .unreadable])

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: Self.started.addingTimeInterval(60), systemLog: systemLog
            )
            let session = try #require(await sut.previousSessions().first)
            let actual = try await sut.log(of: session).lines.map(\.text)

            #expect(actual == ["Feed loaded", "Checkout failed"])
            #expect(systemLog.reads.count == 2)
        }

        @Test("Merging keeps each entry as many times as the read holding the most of it, in time order")
        func mergesDuplicates() throws {
            let header = try JSONEncoder().encode(ConsoleSessionHeader(started: Self.started, bundle: .main, processIdentifier: 4242))
            let tail = try #require(ConsoleSessionTail(name: "earlier", data: header + Data("\n".utf8)))
            let retry = LogLine(timestamp: Self.started.addingTimeInterval(2), text: "Retrying", source: .oslog, level: .info)
            var sut = ConsoleSystemLogReads(tail)

            sut.add([retry, retry])
            sut.add([Self.checkoutFailed, retry, Self.lastKept])
            let actual = sut.lines.map(\.text)

            #expect(actual == ["Feed loaded", "Retrying", "Retrying", "Checkout failed"])
            // The second read found two entries the first lacked.
            #expect(sut.needsAnother)
        }
    }
#endif
