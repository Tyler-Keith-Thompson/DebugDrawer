#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    // The model over a recorder whose storage is in memory, holding sessions written as an
    // earlier launch's recorder would write them.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkSessionsModelTests {
        @Test("Reloading lists the earlier sessions, the newest first, without the current one")
        func reloadLists() async throws {
            let storage = FakeNetworkSessionStorage()
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), method: "GET", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            var expected: [String] = []
            for launch in 0 ..< 2 {
                let earlier = NetworkSessionRecorder(
                    try NetworkSessionPersistence(storage: storage),
                    started: Date(timeIntervalSince1970: 1_800_000_000 + Double(launch) * 60)
                )
                earlier.record(entry, original: nil, redaction: .standard)
                _ = await earlier.previousSessions()
                expected.insert(earlier.currentName, at: 0)
            }
            let current = NetworkSessionRecorder(try NetworkSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_600))
            current.record(entry, original: nil, redaction: .standard)
            let sut = NetworkSessionsModel(recorder: current)

            await sut.reload()

            #expect(sut.sessions.map(\.id) == expected)
        }

        @Test("A session that can't be read gives no log and is named unreadable, until one is read")
        func unreadable() async throws {
            let storage = FakeNetworkSessionStorage()
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), method: "GET", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            let earlier = NetworkSessionRecorder(try NetworkSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_000))
            earlier.record(entry, original: nil, redaction: .standard)
            _ = await earlier.previousSessions()
            let sut = NetworkSessionsModel(recorder: NetworkSessionRecorder(
                try NetworkSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_060)
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
            #expect(read?.entries.map(\.url) == ["https://api.example.com/v1/orders"])
            #expect(sut.unreadable == nil)
        }

        @Test("Deleting a session removes it from the disk and the list")
        func delete() async throws {
            let storage = FakeNetworkSessionStorage()
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), method: "GET", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
            )
            var names: [String] = []
            for launch in 0 ..< 2 {
                let earlier = NetworkSessionRecorder(
                    try NetworkSessionPersistence(storage: storage),
                    started: Date(timeIntervalSince1970: 1_800_000_000 + Double(launch) * 60)
                )
                earlier.record(entry, original: nil, redaction: .standard)
                _ = await earlier.previousSessions()
                names.append(earlier.currentName)
            }
            let sut = NetworkSessionsModel(recorder: NetworkSessionRecorder(
                try NetworkSessionPersistence(storage: storage), started: Date(timeIntervalSince1970: 1_800_000_600)
            ))
            await sut.reload()

            await sut.delete([names[0]])

            #expect(sut.sessions.map(\.id) == [names[1]])
            #expect(storage.sessions.keys.sorted() == [names[1]])
        }

        @Test("With no recorder started, nothing is listed")
        func notStarted() async {
            let sut = NetworkSessionsModel()

            await sut.reload()

            #expect(sut.sessions.isEmpty)
        }
    }
#endif
