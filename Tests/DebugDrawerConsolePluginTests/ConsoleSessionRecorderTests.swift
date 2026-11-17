#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    // The production file storage, in a temporary directory of the test's own; each recorder made
    // over a directory is a launch of the app. Listing the earlier sessions runs on the recorder's
    // queue after every line before it, so a test awaits it before it looks at the disk.
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleSessionRecorderTests {
        @Test("Lines one launch's store ingests are viewable under Previous in a store made over the same directory")
        @MainActor func previousSessionAfterRelaunch() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let persistence = ConsoleSessionPersistence(storage: _ConsoleSessionStorage(directory: directory))
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let first = ConsoleSessionRecorder(persistence, started: started)
            let firstStore = ConsoleLogStore()
            firstStore.persist(to: first)
            firstStore.ingest(LogLine(timestamp: started.addingTimeInterval(1), text: "App launched", source: .oslog, level: .info))
            firstStore.ingest(LogLine(timestamp: started.addingTimeInterval(2), text: "Fetching feed", source: .stdout, level: .debug))
            firstStore.ingest(LogLine(timestamp: started.addingTimeInterval(3), text: "Decoding failed", source: .stderr, level: .error))
            let firstSees = await first.previousSessions()

            let second = ConsoleSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_000_100))
            let sut = ConsoleLogStore()
            sut.persist(to: second)
            let sessions = ConsoleSessionsModel(recorder: second)
            await sessions.reload()
            let session = try #require(sessions.sessions.first)
            let log = try #require(await sessions.log(of: session.id))
            sut.showPrevious(log)
            let actual = sut.shownLines

            #expect(firstSees.isEmpty)
            #expect(sessions.sessions.map(\.id) == [first.currentName])
            #expect(session.started == started)
            #expect(log.header?.started == "2027-01-15T08:00:00.000Z")
            #expect(sut.source == .previous)
            #expect(actual.map(\.text) == ["App launched", "Fetching feed", "Decoding failed"])
            #expect(actual.map(\.level) == [.info, .debug, .error])
            #expect(actual.map(\.source) == [.oslog, .stdout, .stderr])
            #expect(actual.map(\.timestamp) == [1, 2, 3].map { started.addingTimeInterval($0) })
            #expect(log.skippedLines == 0)
        }

        @Test("A session with a torn last line, as a crash mid-write leaves it, reads every line before it and counts the torn one")
        func tornLastLine() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storage = _ConsoleSessionStorage(directory: directory)
            let persistence = ConsoleSessionPersistence(storage: storage)
            let first = ConsoleSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_000_000))
            for index in 1 ... 2 {
                first.record(LogLine(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), text: "line \(index)", source: .oslog, level: .info
                ))
            }
            _ = await first.previousSessions()
            try storage.append(Data(#"{"level":"info","source":"oslog","te"#.utf8), toSessionNamed: first.currentName)

            let sut = ConsoleSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_000_100))
            let session = try #require(await sut.previousSessions().first)
            let actual = try await sut.log(of: session)

            #expect(actual.lines.map(\.text) == ["line 1", "line 2"])
            #expect(actual.skippedLines == 1)
        }

        @Test("Each launch deletes the oldest sessions beyond maxSessions, keeping the newest")
        func pruneByCount() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let persistence = ConsoleSessionPersistence(maxSessions: 2, storage: _ConsoleSessionStorage(directory: directory))
            var names: [String] = []
            for launch in 0 ..< 4 {
                let recorder = ConsoleSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_000_000 + Double(launch) * 60))
                recorder.record(LogLine(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_001 + Double(launch) * 60), text: "launch \(launch)",
                    source: .oslog, level: .info
                ))
                _ = await recorder.previousSessions()
                names.append(recorder.currentName)
            }
            let expected = [names[3], names[2]]

            let sut = ConsoleSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_001_000))
            let actual = await sut.previousSessions().map(\.id)
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))

            #expect(actual == expected)
            #expect(files.sorted() == expected.sorted())
        }

        @Test("Once the current session's writes take the sessions past maxBytes, the oldest earlier session is deleted, and only it")
        func pruneBySizeWhileWriting() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storage = _ConsoleSessionStorage(directory: directory)
            let roomy = ConsoleSessionPersistence(storage: storage)
            let line = LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_001), text: "Feed loaded", source: .oslog, level: .info)
            let oldest = ConsoleSessionRecorder(roomy, started: Date(timeIntervalSince1970: 1_800_000_000))
            oldest.record(line)
            _ = await oldest.previousSessions()
            let newer = ConsoleSessionRecorder(roomy, started: Date(timeIntervalSince1970: 1_800_000_060))
            newer.record(line)
            _ = await newer.previousSessions()
            let sizes = try storage.sessionFiles().reduce(into: [String: Int]()) { $0[$1.name] = $1.byteCount }
            let oldestBytes = try #require(sizes[oldest.currentName])
            let newerBytes = try #require(sizes[newer.currentName])
            // Room for both sessions at launch, and for the next one's header and line, as large
            // as either's, only once one goes.
            let tight = ConsoleSessionPersistence(maxBytes: oldestBytes + newerBytes + 10, storage: storage)

            let sut = ConsoleSessionRecorder(tight, started: Date(timeIntervalSince1970: 1_800_000_120))
            let atLaunch = await sut.previousSessions().map(\.id)
            sut.record(line)
            let afterWriting = await sut.previousSessions().map(\.id)
            let current = try storage.sessionFiles().first { $0.name == sut.currentName }

            #expect(atLaunch == [newer.currentName, oldest.currentName])
            #expect(afterWriting == [newer.currentName])
            #expect(current?.byteCount == oldestBytes)
        }

        @Test("A launch deletes the oldest sessions, oldest first, until those kept fit in maxBytes")
        func pruneBySizeAtLaunch() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storage = _ConsoleSessionStorage(directory: directory)
            let line = LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_001), text: "Feed loaded", source: .oslog, level: .info)
            var names: [String] = []
            for launch in 0 ..< 3 {
                let recorder = ConsoleSessionRecorder(
                    ConsoleSessionPersistence(storage: storage),
                    started: Date(timeIntervalSince1970: 1_800_000_000 + Double(launch) * 60)
                )
                recorder.record(line)
                _ = await recorder.previousSessions()
                names.append(recorder.currentName)
            }
            let sizes = try storage.sessionFiles().map(\.byteCount)
            let largest = sizes.max() ?? 0
            // Room for two of the three, so only the oldest goes.
            let maxBytes = 2 * largest + 1
            let expected = [names[2], names[1]]

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(maxBytes: maxBytes, storage: storage),
                started: Date(timeIntervalSince1970: 1_800_001_000)
            )
            let actual = await sut.previousSessions().map(\.id)
            let files = try FileManager.default.contentsOfDirectory(atPath: directory.path(percentEncoded: false))

            #expect(actual == expected)
            #expect(files.sorted() == expected.sorted())
        }

        @Test("A current session that alone would pass maxBytes keeps the lines that fit, within the limit, and is never deleted")
        func currentSessionTruncated() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storage = _ConsoleSessionStorage(directory: directory)
            let maxBytes = 1_000
            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(maxBytes: maxBytes, storage: storage),
                started: Date(timeIntervalSince1970: 1_800_000_000)
            )
            let recorded = (0 ..< 20).map { index in
                LogLine(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_001 + Double(index)), text: "Request \(index) finished",
                    source: .oslog, level: .info
                )
            }

            for line in recorded {
                sut.record(line)
                // One at a time, so each is its own write.
                _ = await sut.previousSessions()
            }
            let file = try #require(try storage.sessionFiles().first { $0.name == sut.currentName })
            let summary = try #require(ConsoleSessionSummary(file))
            let actual = ConsoleSessionLog(summary: summary, data: try storage.contents(ofSessionNamed: sut.currentName)).lines.map(\.text)

            #expect(file.byteCount <= maxBytes)
            #expect(!actual.isEmpty)
            #expect(actual.count < recorded.count)
            #expect(actual == recorded.prefix(actual.count).map(\.text))
        }

        @Test("A line too large for the room left isn't written, and a smaller one after it is")
        func oversizedLineSkipped() async throws {
            let storage = FakeConsoleSessionStorage()
            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(maxBytes: 3_000, storage: storage),
                started: Date(timeIntervalSince1970: 1_800_000_000)
            )
            let dump = LogLine(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), text: String(repeating: "a", count: 10_000), source: .stdout, level: .info
            )
            let ping = LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_002), text: "ping", source: .oslog, level: .info)

            sut.record(dump)
            _ = await sut.previousSessions()
            sut.record(ping)
            _ = await sut.previousSessions()
            let data = try storage.contents(ofSessionNamed: sut.currentName)
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(name: sut.currentName, byteCount: data.count)))
            let actual = ConsoleSessionLog(summary: summary, data: data)

            #expect(actual.header != nil)
            #expect(actual.lines.map(\.text) == ["ping"])
            #expect(data.count <= 3_000)
        }

        @Test("Off, nothing is written and the sessions earlier launches kept are deleted at launch")
        func off() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let storage = _ConsoleSessionStorage(directory: directory)
            let line = LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_001), text: "Feed loaded", source: .oslog, level: .info)
            let earlier = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_000))
            earlier.record(line)
            _ = await earlier.previousSessions()
            let before = try storage.sessionFiles().count

            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(maxSessions: 0, storage: storage),
                started: Date(timeIntervalSince1970: 1_800_000_060)
            )
            sut.record(line)
            let listed = await sut.previousSessions()
            let actual = try storage.sessionFiles()

            #expect(before == 1)
            #expect(listed.isEmpty)
            #expect(actual.isEmpty)
            #expect(ConsoleSessionPersistence.off.maxSessions == 0)
            #expect(ConsoleSessionPersistence.standard.maxSessions == 5)
            #expect(ConsoleSessionPersistence.standard.maxBytes == 20_000_000)
        }

        @Test("Lines recorded from many tasks at once are each written once, as a whole line")
        func concurrentRecords() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let persistence = ConsoleSessionPersistence(storage: _ConsoleSessionStorage(directory: directory))
            let sut = ConsoleSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_000_000), capacity: 1_000)
            let count = 300
            let expected = Set((0 ..< count).map { "line \($0)" })

            await withTaskGroup(of: Void.self) { group in
                for index in 0 ..< count {
                    group.addTask {
                        sut.record(LogLine(
                            timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: "line \(index)", source: .oslog, level: .info
                        ))
                    }
                }
            }
            _ = await sut.previousSessions()
            let next = ConsoleSessionRecorder(persistence, started: Date(timeIntervalSince1970: 1_800_000_060))
            let session = try #require(await next.previousSessions().first)
            let actual = try await next.log(of: session)

            #expect(actual.lines.count == count)
            #expect(Set(actual.lines.map(\.text)) == expected)
            #expect(actual.skippedLines == 0)
        }

        @Test("While a write is slow, at most capacity lines wait, the earliest going first")
        func boundedWhileWriting() async throws {
            let storage = FakeConsoleSessionStorage(holdsAppends: true)
            let sut = ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage),
                started: Date(timeIntervalSince1970: 1_800_000_000), capacity: 3
            )
            var started = storage.appendsStarted.makeAsyncIterator()
            sut.record(LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_000), text: "line 0", source: .oslog, level: .info))
            await started.next()
            for index in 1 ... 10 {
                sut.record(LogLine(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)), text: "line \(index)", source: .oslog, level: .info
                ))
            }

            storage.releaseAppend()
            await started.next()
            storage.releaseAppend()
            _ = await sut.previousSessions()
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(name: sut.currentName, byteCount: 0)))
            let actual = ConsoleSessionLog(summary: summary, data: try storage.contents(ofSessionNamed: sut.currentName))
            let expected = ["line 0", "line 8", "line 9", "line 10"]

            #expect(actual.lines.map(\.text) == expected)
        }

        @Test("The file starts with the session's header, then one JSON line per log line, with its time, level, source and text")
        func headerAndLineFormat() async throws {
            let storage = FakeConsoleSessionStorage()
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let sut = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: storage), started: started)
            let expected = #"{"level":"fault","source":"oslog","text":"[com.shop/cart] Checkout \"failed\"\nretrying","#
                + #""time":"2027-01-15T08:00:00.250Z"}"#

            sut.record(LogLine(
                timestamp: started.addingTimeInterval(0.25), text: "[com.shop/cart] Checkout \"failed\"\nretrying", source: .oslog, level: .fault
            ))
            _ = await sut.previousSessions()
            let data = try storage.contents(ofSessionNamed: sut.currentName)
            let rows = data.split(separator: UInt8(ascii: "\n")).map { String(bytes: $0, encoding: .utf8) ?? "" }
            let headerRow = try #require(rows.first)
            let header = try JSONDecoder().decode(ConsoleSessionHeader.self, from: Data(headerRow.utf8))

            #expect(rows.count == 2)
            #expect(header.format == 1)
            #expect(header.started == "2027-01-15T08:00:00.000Z")
            #expect(headerRow.hasPrefix(#"{"app":"#))
            #expect(headerRow.contains(#""debugDrawerConsoleSession":1"#))
            #expect(rows.last == expected)
        }

        @Test("Deleting removes the earlier sessions named, and never the current one")
        func delete() async throws {
            let storage = FakeConsoleSessionStorage()
            let line = LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_001), text: "Feed loaded", source: .oslog, level: .info)
            let earlier = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_000))
            earlier.record(line)
            _ = await earlier.previousSessions()
            let sut = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_060))
            sut.record(line)

            await sut.delete([earlier.currentName, sut.currentName])
            let listed = await sut.previousSessions()

            #expect(listed.isEmpty)
            #expect(Array(storage.sessions.keys) == [sut.currentName])
        }
    }
#endif
