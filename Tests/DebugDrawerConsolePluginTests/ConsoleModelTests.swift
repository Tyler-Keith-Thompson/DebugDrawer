#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    // The model is read and driven here as an out-of-process reader would: through its snapshot,
    // encoded and decoded, and commands, encoded and decoded, with no view. Lines reach the store
    // through an earlier session shown under Previous, which shows them at once; captured lines
    // arrive through the store's batching, on a timer the tests can't steer.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleModelTests {
        @Test("A snapshot with an earlier session's page, a pattern search, mutes and a time range encodes to JSON and decodes equal")
        func snapshotRoundTrips() async throws {
            let header = #"{"debugDrawerConsoleSession":1,"started":"2027-01-15T08:00:00.000Z","app":"Shop","appVersion":"2.1 (40)"}"#
            let rows = [
                #"{"level":"info","source":"oslog","subsystem":"com.example.feed","category":"net","#
                    + #""text":"Feed loaded","time":"2027-01-15T08:00:01.000Z"}"#,
                #"{"level":"error","source":"sink","subsystem":"com.example.cart","category":"ui","#
                    + #""text":"Cart failed","time":"2027-01-15T08:00:02.000Z","metadata":{"order":"1042"}}"#,
                #"{"level":"debug","source":"stdout","text":"printed","time":"2027-01-15T08:00:03.000Z"}"#
            ]
            let data = Data(([header] + rows).joined(separator: "\n").utf8)
            let summary = try #require(ConsoleSessionSummary(ConsoleSessionFile(
                name: ConsoleSessionSummary.name(started: Date(timeIntervalSince1970: 1_800_000_000), id: UUID()), byteCount: data.count
            )))
            let store = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            let sut = ConsoleModel(store: store, sessions: ConsoleSessionsModel())
            await store.showPrevious(ConsoleSessionLog(summary: summary, data: data))
            sut.perform(ConsoleCommand(.filter(.setSearchIsRegularExpression(true))))
            sut.perform(ConsoleCommand(.filter(.setSearchText("fe+d|cart"))))
            sut.perform(ConsoleCommand(.filter(.mute(.category("ui", subsystem: "com.example.cart")))))
            sut.perform(ConsoleCommand(.filter(.setShowsMuted(true))))
            sut.perform(ConsoleCommand(.filter(.setTimeRange(.last(minutes: 5)))))
            let snapshot = sut.snapshot

            let encoded = try JSONEncoder().encode(snapshot)
            let actual = try JSONDecoder().decode(ConsoleSnapshot.self, from: encoded)

            #expect(actual == snapshot)
            #expect(actual.log.source == .previous)
            #expect(actual.log.shownLines.map(\.text) == ["Feed loaded", "Cart failed"])
            #expect(actual.log.shownLines.last?.metadata == ["order": "1042"])
            #expect(actual.log.mutedCount == 1)
            #expect(actual.log.filter.mutes == [.category("ui", subsystem: "com.example.cart")])
        }

        @Test("A search that isn't a pattern carries its issue in the snapshot, and the filter keeps the last one that was")
        func invalidPatternRoundTrips() throws {
            let sut = ConsoleModel(store: ConsoleLogStore(muteStorage: FakeConsoleMuteStorage()), sessions: ConsoleSessionsModel())
            sut.perform(ConsoleCommand(.filter(.setSearchIsRegularExpression(true))))
            sut.perform(ConsoleCommand(.filter(.setSearchText("order"))))
            sut.perform(ConsoleCommand(.filter(.setSearchText("order("))))

            let actual = try JSONDecoder().decode(ConsoleSnapshot.self, from: JSONEncoder().encode(sut.snapshot))

            #expect(actual.log.searchText == "order(")
            #expect(actual.log.searchIssue == ConsoleSearch.InvalidPattern())
            #expect(actual.log.filter.search == sut.snapshot.log.filter.search)
        }

        @Test("A command encoded to JSON and decoded does to the model what the original would, through a direct transport")
        func commandsRoundTrip() throws {
            let storage = FakeConsoleMuteStorage()
            let store = ConsoleLogStore(muteStorage: storage)
            let sut = DebugDrawerPluginTransport.direct(to: ConsoleModel(store: store, sessions: ConsoleSessionsModel()))
            let commands = [
                ConsoleCommand(.filter(.setLevel(.error))),
                ConsoleCommand(.filter(.mute(.subsystem("com.example.feed")))),
                ConsoleCommand(.filter(.mute(.subsystem("com.example.ads")))),
                ConsoleCommand(.filter(.unmute(.subsystem("com.example.ads")))),
                ConsoleCommand(.filter(.setTimeRange(.since(Date(timeIntervalSince1970: 1_800_000_000)))))
            ]

            for command in commands {
                let decoded = try JSONDecoder().decode(ConsoleCommand.self, from: JSONEncoder().encode(command))
                sut.send(decoded)
            }

            let actual = sut.snapshot.log.filter
            #expect(actual.level == .error)
            #expect(actual.mutes == [.subsystem("com.example.feed")])
            #expect(actual.timeRange == .since(Date(timeIntervalSince1970: 1_800_000_000)))
            #expect(store.filterLevel == .error)
            #expect(storage.data != nil)
        }
    }
#endif
