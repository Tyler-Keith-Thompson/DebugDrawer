#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    @testable import DebugDrawerNetworkPlugin
    @testable import DebugDrawerRemote
    import Foundation
    import Network
    import Testing

    // What a person at the Mac viewer sees of the device: the app's real Network and Console
    // models (their storage in memory), served over the network transport on 127.0.0.1, and a
    // viewer that pairs and watches a request and a log line arrive as the app makes them. Each
    // wait is for the snapshot that step should produce. The Console's own pipeline batches
    // captured lines on a 100 ms timer, which delivers the line; the test waits on the snapshot,
    // not on time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkTransportLiveTests {
        @Test("A request and a log line the app records appear live in a paired viewer, and the viewer's filter reaches the app")
        func networkAndConsoleLive() async throws {
            let storage = InMemoryNetworkStorage()
            let networkStore = NetworkStore(
                ignoreStorage: storage,
                webSocketRecorder: NetworkWebSocketRecorder(connectionCapacity: 10, frameCapacity: 10)
            )
            let network = NetworkModel(
                store: networkStore,
                mocks: NetworkMocksModel(storage: storage, active: NetworkMockRules()),
                conditions: NetworkConditionsModel(
                    storage: storage, active: NetworkConditions(),
                    scheduler: IdleNetworkConditionScheduler(), random: ZeroNetworkConditionRandomSource()
                ),
                replays: NetworkReplayModel(sender: UnsentNetworkReplaySender()),
                sessions: NetworkSessionsModel()
            )
            let consoleStore = ConsoleLogStore(muteStorage: InMemoryConsoleMuteStorage())
            let console = ConsoleModel(store: consoleStore, sessions: ConsoleSessionsModel())
            let registry = DebugDrawerModelRegistry()
            registry.register(network, id: NetworkPlugin().id)
            registry.register(console, id: ConsolePlugin().id)
            let server = DebugDrawerNetworkServer(registry: registry, configuration: .loopback)
            try await server.start()
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let sut = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Studio Mac")
            var shown: DebugDrawerPairingRequest?
            for await requests in server.$pairingRequests.values where !requests.isEmpty {
                shown = requests.first
                break
            }
            try await sut.pair(code: try #require(shown).code)
            let request = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_000), method: "POST", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: ["Content-Type": "application/json"],
                requestBody: Data(#"{"sku":"A1"}"#.utf8), statusCode: 201, duration: 0.12, isComplete: true
            )
            let line = LogLine(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), text: "Order 1042 placed", source: .sink, level: .info,
                subsystem: "com.example.shop", category: "checkout"
            )

            let remoteNetwork = try await sut.connect(toPlugin: NetworkPlugin().id, snapshot: NetworkSnapshot.self, command: NetworkCommand.self)
            let remoteConsole = try await sut.connect(toPlugin: ConsolePlugin().id, snapshot: ConsoleSnapshot.self, command: ConsoleCommand.self)
            let networkBefore = remoteNetwork.snapshot.log.captured
            let consoleBefore = remoteConsole.snapshot.log.lines
            networkStore.recordStart(request)
            for await snapshot in remoteNetwork.snapshots() where !snapshot.log.captured.isEmpty {
                break
            }
            consoleStore.ingest(line)
            for await snapshot in remoteConsole.snapshots() where !snapshot.log.lines.isEmpty {
                break
            }
            remoteNetwork.send(NetworkCommand(.log(.setFilterText("orders"))))
            for await snapshot in remoteNetwork.snapshots() where snapshot.log.filterText == "orders" {
                break
            }

            #expect(networkBefore.isEmpty)
            #expect(consoleBefore.isEmpty)
            #expect(remoteNetwork.snapshot.log.captured == [request])
            #expect(remoteNetwork.snapshot.log.filteredEntries.map(\.url) == ["https://api.example.com/v1/orders"])
            #expect(remoteConsole.snapshot.log.lines.map(\.text) == ["Order 1042 placed"])
            #expect(remoteConsole.snapshot.log.lines.first?.subsystem == "com.example.shop")
            #expect(network.snapshot.log.filterText == "orders")
            server.stop()
        }
    }
#endif
