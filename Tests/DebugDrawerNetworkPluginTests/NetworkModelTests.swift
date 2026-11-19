#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    // The model is read and driven here as an out-of-process reader would: through its snapshot,
    // encoded and decoded, and commands, encoded and decoded, with no view.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkModelTests {
        @Test("A snapshot holding every kind of value the plugin shows encodes to JSON and decodes equal")
        func snapshotRoundTrips() async throws {
            let storage = FakeNetworkMockStorage()
            let store = NetworkStore(
                ignoreStorage: FakeNetworkIgnoreListStorage(),
                webSocketRecorder: NetworkWebSocketRecorder(connectionCapacity: 10, frameCapacity: 10)
            )
            let replays = NetworkReplayModel(sender: FakeNetworkReplaySender())
            let sut = NetworkModel(
                store: store,
                mocks: NetworkMocksModel(storage: storage, active: NetworkMockRules()),
                conditions: NetworkConditionsModel(
                    storage: FakeNetworkConditionStorage(), active: NetworkConditions(),
                    scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
                ),
                replays: replays,
                sessions: NetworkSessionsModel()
            )
            let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let truncated = NetworkEntry(
                timestamp: start, method: "POST", url: "https://api.example.com/v1/upload?draft=1", host: "api.example.com",
                path: "/v1/upload", requestHeaders: ["Content-Type": "application/json"], requestBody: Data(#"{"name":"#.utf8),
                requestBodySize: 4096, statusCode: 201, responseHeaders: ["Content-Type": "application/json"],
                responseBody: Data(#"{"id":42}"#.utf8), responseBodySize: 9, duration: 0.25, isComplete: true,
                metrics: NetworkTimingMetrics(
                    phases: [.init(kind: .dns, start: 0, duration: 0.01), .init(kind: .response, start: 0.2, duration: 0.05)],
                    protocolName: "h2", isReusedConnection: false, isCacheHit: false
                ),
                mockRuleName: "Upload",
                conditionEffect: NetworkConditionEffect(profileName: "3G", latency: .milliseconds(300), bandwidth: 50_000, failure: nil)
            )
            let failed = NetworkEntry(
                timestamp: start + 1, method: "GET", url: "https://cdn.example.net/a.png", host: "cdn.example.net", path: "/a.png",
                requestHeaders: [:], requestBody: nil, duration: 1, error: "The request timed out.", isComplete: true
            )
            store.recordStart(truncated)
            store.recordStart(failed)
            var connection = NetworkWebSocketConnection(url: "wss://chat.example.com/room", protocols: ["chat"], opened: start)
            connection.record(NetworkWebSocketFrame(direction: .sent, kind: .text, payload: Data("hello".utf8), timestamp: start + 2), capacity: 10)
            connection.record(NetworkWebSocketFrame(direction: .received, kind: .binary, payload: Data([1, 2]), timestamp: start + 3), capacity: 10)
            connection.end(.closed(NetworkWebSocketClose(side: .server, code: 1000, reason: "bye", timestamp: start + 4)))
            store.showWebSockets([connection])
            let summary = try #require(NetworkSessionSummary(NetworkSessionFile(
                name: NetworkSessionSummary.name(started: start, id: UUID()), byteCount: 0
            )))
            store.showPrevious(NetworkSessionLog(summary: summary, data: Data()))
            sut.perform(NetworkCommand(.log(.setSource(.captured))))
            sut.perform(NetworkCommand(.log(.setFilterText("example"))))
            sut.perform(NetworkCommand(.log(.setFilterStatus(.errors))))
            sut.perform(NetworkCommand(.log(.ignore(try NetworkIgnoredDomain(parsing: "tracking.example.org")))))
            sut.perform(NetworkCommand(.log(.setShowsIgnored(true))))
            sut.perform(NetworkCommand(.mocks(.save(NetworkMockRule(
                name: "Greeting", matcher: .init(methods: ["GET"], host: .wildcard("*.example.com"), path: .regex("^/v[0-9]+/greeting$")),
                response: .init(status: 200, body: .text("hi"), contentType: "text/plain")
            )))))
            sut.perform(NetworkCommand(.conditions(.save(NetworkConditionProfile(
                name: "Flaky", host: .exact("api.example.com"), latency: .seconds(2), failureRate: 20, failure: .timedOut
            )))))
            await replays.resend(truncated)
            let snapshot = sut.snapshot

            let encoded = try JSONEncoder().encode(snapshot)
            let actual = try JSONDecoder().decode(NetworkSnapshot.self, from: encoded)

            #expect(actual == snapshot)
            #expect(actual.log.captured.map(\.id) == [failed.id, truncated.id])
            #expect(actual.log.filteredEntries.map(\.id) == [failed.id])
            #expect(actual.log.webSockets.first?.frames.count == 2)
            #expect(actual.log.previous?.summary == summary)
            #expect(actual.mockRules.map(\.name) == ["Greeting"])
            #expect(actual.conditionProfiles.map(\.name) == ["Flaky"])
            #expect(actual.replayStatuses[truncated.id] != nil)
        }

        @Test("A command encoded to JSON and decoded does to the model what the original would")
        func commandsRoundTrip() throws {
            let sut = NetworkModel(
                store: NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage()),
                mocks: NetworkMocksModel(storage: FakeNetworkMockStorage(), active: NetworkMockRules()),
                conditions: NetworkConditionsModel(
                    storage: FakeNetworkConditionStorage(), active: NetworkConditions(),
                    scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
                ),
                replays: NetworkReplayModel(sender: FakeNetworkReplaySender()),
                sessions: NetworkSessionsModel()
            )
            let rule = NetworkMockRule(name: "Orders", matcher: .init(path: .exact("/orders")), response: .init(status: 404))
            let commands = [
                NetworkCommand(.log(.setFilterText("orders"))),
                NetworkCommand(.log(.setFilterStatus(.clientError))),
                NetworkCommand(.mocks(.save(rule))),
                NetworkCommand(.mocks(.setEnabled(rule.id, false))),
                NetworkCommand(.log(.ignore(try NetworkIgnoredDomain(parsing: "ads.example.com"))))
            ]

            for command in commands {
                let decoded = try JSONDecoder().decode(NetworkCommand.self, from: JSONEncoder().encode(command))
                sut.perform(decoded)
            }

            let actual = sut.snapshot
            #expect(actual.log.filterText == "orders")
            #expect(actual.log.filterStatus == .clientError)
            #expect(actual.mockRules.map(\.id) == [rule.id])
            #expect(actual.mockRules.first?.isEnabled == false)
            #expect(actual.log.ignoredDomains.map(\.name) == ["ads.example.com"])
        }

        @Test("Through a direct transport, a view's text field reads back the filter it just set, and Clear empties the log")
        func directTransportDrivesTheLog() {
            let store = NetworkStore(
                ignoreStorage: FakeNetworkIgnoreListStorage(),
                webSocketRecorder: NetworkWebSocketRecorder(connectionCapacity: 10, frameCapacity: 10)
            )
            let model = NetworkModel(
                store: store,
                mocks: NetworkMocksModel(storage: FakeNetworkMockStorage(), active: NetworkMockRules()),
                conditions: NetworkConditionsModel(
                    storage: FakeNetworkConditionStorage(), active: NetworkConditions(),
                    scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
                ),
                replays: NetworkReplayModel(sender: FakeNetworkReplaySender()),
                sessions: NetworkSessionsModel()
            )
            let sut = DebugDrawerPluginTransport.direct(to: model)
            for path in ["/orders", "/users"] {
                store.recordStart(NetworkEntry(
                    timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET", url: "https://api.example.com\(path)",
                    host: "api.example.com", path: path, requestHeaders: [:], requestBody: nil, statusCode: 200, isComplete: true
                ))
            }

            sut.send(NetworkCommand(.log(.setFilterText("users"))))
            let filtered = sut.snapshot.log.filteredEntries.map(\.path)
            sut.send(NetworkCommand(.log(.clearShown)))

            #expect(filtered == ["/users"])
            #expect(sut.snapshot.log.captured.isEmpty)
            #expect(store.entries.isEmpty)
        }

        @Test("Mock This of a body that isn't text names a file the upload command keeps in the storage")
        func mockThisBinaryBody() throws {
            let storage = FakeNetworkMockStorage()
            let sut = NetworkModel(
                store: NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage()),
                mocks: NetworkMocksModel(storage: storage, active: NetworkMockRules()),
                conditions: NetworkConditionsModel(
                    storage: FakeNetworkConditionStorage(), active: NetworkConditions(),
                    scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
                ),
                replays: NetworkReplayModel(sender: FakeNetworkReplaySender()),
                sessions: NetworkSessionsModel()
            )
            let bytes = Data([0xFF, 0xD8, 0xFF, 0x00])
            let entry = NetworkEntry(
                timestamp: Date(timeIntervalSinceReferenceDate: 800_000_000), method: "GET",
                url: "https://cdn.test/photo", host: "cdn.test", path: "/photo",
                requestHeaders: [:], requestBody: nil, statusCode: 200, responseHeaders: ["Content-Type": "image/jpeg"],
                responseBody: bytes, isComplete: true
            )
            let prefill = NetworkMockPrefill(mocking: entry)
            let upload = try #require(prefill.upload)

            sut.perform(NetworkCommand(.mocks(.addBody(upload))))
            sut.perform(NetworkCommand(.mocks(.save(prefill.rule))))

            #expect(prefill.rule.response.body == .file(upload.name))
            #expect(storage.body(named: upload.name) == bytes)
            #expect(sut.snapshot.mockRules == [prefill.rule])
        }
    }
#endif
