#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    // The model over a recorder whose storage is in memory, holding sessions written as an
    // earlier launch's recorder would write them.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleSessionsModelTests {
        @Test("Reloading lists the earlier sessions, the newest first, without the current one")
        func reloadLists() async {
            let storage = FakeConsoleSessionStorage()
            let line = LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_001), text: "Feed loaded", source: .oslog, level: .info)
            var expected: [String] = []
            for launch in 0 ..< 2 {
                let earlier = ConsoleSessionRecorder(
                    ConsoleSessionPersistence(storage: storage),
                    started: Date(timeIntervalSince1970: 1_800_000_000 + Double(launch) * 60)
                )
                earlier.record(line)
                _ = await earlier.previousSessions()
                expected.insert(earlier.currentName, at: 0)
            }
            let current = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_600))
            current.record(line)
            let sut = ConsoleSessionsModel(recorder: current)

            await sut.reload()

            #expect(sut.sessions.map(\.id) == expected)
        }

        @Test("A session that can't be read gives no log and is named unreadable, until one is read")
        func unreadable() async throws {
            let storage = FakeConsoleSessionStorage()
            let line = LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_001), text: "Feed loaded", source: .oslog, level: .info)
            let earlier = ConsoleSessionRecorder(ConsoleSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_000))
            earlier.record(line)
            _ = await earlier.previousSessions()
            let sut = ConsoleSessionsModel(recorder: ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_060)
            ))
            await sut.reload()
            let id = try #require(sut.sessions.first?.id)

            storage.failsReading = true
            let failed = await sut.log(of: id)
            let named = sut.unreadable?.id
            storage.failsReading = false
            let read = await sut.log(of: id)

            #expect(failed == nil)
            #expect(named == id)
            #expect(read?.lines.map(\.text) == ["Feed loaded"])
            #expect(sut.unreadable == nil)
        }

        @Test("Deleting a session removes it from the disk and the list")
        func delete() async throws {
            let storage = FakeConsoleSessionStorage()
            let line = LogLine(timestamp: Date(timeIntervalSince1970: 1_800_000_001), text: "Feed loaded", source: .oslog, level: .info)
            var names: [String] = []
            for launch in 0 ..< 2 {
                let earlier = ConsoleSessionRecorder(
                    ConsoleSessionPersistence(storage: storage),
                    started: Date(timeIntervalSince1970: 1_800_000_000 + Double(launch) * 60)
                )
                earlier.record(line)
                _ = await earlier.previousSessions()
                names.append(earlier.currentName)
            }
            let sut = ConsoleSessionsModel(recorder: ConsoleSessionRecorder(
                ConsoleSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_600)
            ))
            await sut.reload()

            await sut.delete([names[0]])

            #expect(sut.sessions.map(\.id) == [names[1]])
            #expect(storage.sessions.keys.sorted() == [names[1]])
        }

        @Test("With no recorder started, nothing is listed")
        func notStarted() async {
            let sut = ConsoleSessionsModel()

            await sut.reload()

            #expect(sut.sessions.isEmpty)
        }

        @Test("The store shows the captured lines until an earlier session is shown, and the captured ones again once it is hidden")
        func storeSources() throws {
            let started = Date(timeIntervalSince1970: 1_800_000_000)
            let data = Data(#"{"level":"error","source":"stderr","text":"Earlier crash","time":"2027-01-15T08:00:01.000Z"}"#.utf8)
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: started, id: UUID()), byteCount: data.count
            )))
            let sut = ConsoleLogStore()

            let before = sut.source
            sut.showPrevious(ConsoleSessionLog(summary: summary, data: data))
            let shown = sut.shownLines.map(\.text)
            sut.filterLevel = .fault
            let filtered = sut.shownLines.map(\.text)
            sut.hidePrevious()

            #expect(before == .captured)
            #expect(shown == ["Earlier crash"])
            #expect(filtered.isEmpty)
            #expect(sut.source == .captured)
            #expect(sut.previousLog == nil)
            #expect(sut.shownLines.isEmpty)
        }
    }
#endif
