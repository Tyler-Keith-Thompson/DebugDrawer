#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    @testable import DebugDrawerNetworkPlugin
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    // What a person at the sidecar sees of an app: the app's real Console and Network models (their
    // storage in memory), served by the store server, and by the socket server beside it, in a
    // temporary group container, found through the kit's app list and shown by the kit over the
    // store and over the socket. A log line and a request the app records arrive in the plugins the
    // kit hosts, and their views draw them. Each wait is for the snapshot or channel that step should
    // produce: the Console's pipeline batches captured lines on its own timer, which delivers the
    // line, and the test waits on the snapshot, not on time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarHostingTests {
        /// The app's side: its models, and the servers it runs.
        @MainActor
        struct App {
            let network: NetworkModel
            let networkStore: NetworkStore
            let consoleStore: ConsoleLogStore
            let registry = DebugDrawerModelRegistry()

            init() {
                let storage = InMemoryNetworkStorage()
                networkStore = NetworkStore(
                    ignoreStorage: storage,
                    webSocketRecorder: NetworkWebSocketRecorder(connectionCapacity: 10, frameCapacity: 10)
                )
                network = NetworkModel(
                    store: networkStore,
                    mocks: NetworkMocksModel(storage: storage, active: NetworkMockRules()),
                    conditions: NetworkConditionsModel(
                        storage: storage, active: NetworkConditions(),
                        scheduler: IdleNetworkConditionScheduler(), random: ZeroNetworkConditionRandomSource()
                    ),
                    replays: NetworkReplayModel(sender: UnsentNetworkReplaySender()),
                    sessions: NetworkSessionsModel()
                )
                consoleStore = ConsoleLogStore(muteStorage: InMemoryConsoleMuteStorage())
                registry.register(network, id: NetworkPlugin().id)
                registry.register(ConsoleModel(store: consoleStore, sessions: ConsoleSessionsModel()), id: ConsolePlugin().id)
            }
        }

        static let request = NetworkEntry(
            timestamp: Date(timeIntervalSince1970: 1_800_000_000), method: "POST", url: "https://api.example.com/v1/orders",
            host: "api.example.com", path: "/v1/orders", requestHeaders: ["Content-Type": "application/json"],
            requestBody: Data(#"{"sku":"A1"}"#.utf8), statusCode: 201, duration: 0.12, isComplete: true
        )
        static let line = LogLine(
            timestamp: Date(timeIntervalSince1970: 1_800_000_001), text: "Order 1042 placed", source: .sink, level: .info,
            subsystem: "com.example.shop", category: "checkout"
        )

        @Test("Over the store, the kit lists the app and hosts its Console and Network: a line and a request it records show in their views")
        func consoleAndNetworkOverTheStore() async throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarHostingTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let app = App()
            let server = DebugDrawerAppGroupStoreServer(registry: app.registry, directory: store)
            server.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            try server.start()
            let apps = DebugDrawerSidecarAppList(storeDirectory: store)
            let listed = try #require(apps.apps.first)
            var consoleTransport: DebugDrawerPluginTransport<ConsoleSnapshot, ConsoleCommand>?
            var networkTransport: DebugDrawerPluginTransport<NetworkSnapshot, NetworkCommand>?
            let console = DebugDrawerSidecarPlugin(
                id: ConsolePlugin().id, title: "Console", icon: "terminal", snapshot: ConsoleSnapshot.self, command: ConsoleCommand.self
            ) { transport in
                consoleTransport = transport
                return ConsolePlugin(transport: transport)
            }
            let network = DebugDrawerSidecarPlugin(
                id: NetworkPlugin().id, title: "Network", icon: "network", snapshot: NetworkSnapshot.self, command: NetworkCommand.self
            ) { transport in
                networkTransport = transport
                return NetworkPlugin(transport: transport)
            }
            let sut = try DebugDrawerSidecarConnection(app: listed)

            let hostedConsole = try await sut.host(console)
            let hostedNetwork = try await sut.host(network)
            app.consoleStore.ingest(Self.line)
            app.networkStore.recordStart(Self.request)
            for await snapshot in try #require(consoleTransport).snapshots() where !snapshot.log.lines.isEmpty {
                break
            }
            for await snapshot in try #require(networkTransport).snapshots() where !snapshot.log.captured.isEmpty {
                break
            }
            let consoleHeader = try #require(hostedConsole.headerAccessory)
            let networkHeader = try #require(hostedNetwork.headerAccessory)

            #expect(sut.channel == .store)
            #expect(listed.serves(ConsolePlugin().id) && listed.serves(NetworkPlugin().id))
            #expect(sut.hosted.map(\.id) == [ConsolePlugin().id, NetworkPlugin().id])
            #expect(consoleTransport?.snapshot.log.lines.map(\.text) == ["Order 1042 placed"])
            #expect(networkTransport?.snapshot.log.captured == [Self.request])
            #expect(throws: Never.self) { try consoleHeader.inspect().find(text: "1 line") }
            #expect(throws: Never.self) { try networkHeader.inspect().find(text: "1 request") }
            #expect(throws: Never.self) { try hostedNetwork.body.inspect().find(text: "/v1/orders") }
            sut.close()
            server.stop()
        }

        @Test("Over the socket, the kit hosts the app's Console and Network, and a filter set in the kit reaches the app")
        func consoleAndNetworkOverTheSocket() async throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarHostingTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let app = App()
            let storeServer = DebugDrawerAppGroupStoreServer(registry: app.registry, directory: store)
            storeServer.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            let socketPath = storeServer.appDirectory.appending(path: "drawer.sock").path
            let socketServer = DebugDrawerSocketServer(registry: app.registry, socketPath: socketPath)
            try storeServer.start()
            try socketServer.start()
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            var consoleTransport: DebugDrawerPluginTransport<ConsoleSnapshot, ConsoleCommand>?
            var networkTransport: DebugDrawerPluginTransport<NetworkSnapshot, NetworkCommand>?
            let console = DebugDrawerSidecarPlugin(
                id: ConsolePlugin().id, title: "Console", icon: "terminal", snapshot: ConsoleSnapshot.self, command: ConsoleCommand.self
            ) { transport in
                consoleTransport = transport
                return ConsolePlugin(transport: transport)
            }
            let network = DebugDrawerSidecarPlugin(
                id: NetworkPlugin().id, title: "Network", icon: "network", snapshot: NetworkSnapshot.self, command: NetworkCommand.self
            ) { transport in
                networkTransport = transport
                return NetworkPlugin(transport: transport)
            }
            let sut = try DebugDrawerSidecarConnection(app: listed)
            for await channel in sut.$channel.values where channel == .socket {
                break
            }

            let hostedConsole = try await sut.host(console)
            let hostedNetwork = try await sut.host(network)
            app.consoleStore.ingest(Self.line)
            app.networkStore.recordStart(Self.request)
            for await snapshot in try #require(consoleTransport).snapshots() where !snapshot.log.lines.isEmpty {
                break
            }
            for await snapshot in try #require(networkTransport).snapshots() where !snapshot.log.captured.isEmpty {
                break
            }
            networkTransport?.send(NetworkCommand(.log(.setFilterText("orders"))))
            for await snapshot in try #require(networkTransport).snapshots() where snapshot.log.filterText == "orders" {
                break
            }
            let consoleHeader = try #require(hostedConsole.headerAccessory)

            #expect(sut.channel == .socket)
            #expect(consoleTransport?.snapshot.log.lines.first?.subsystem == "com.example.shop")
            #expect(networkTransport?.snapshot.log.filteredEntries.map(\.url) == ["https://api.example.com/v1/orders"])
            #expect(app.network.snapshot.log.filterText == "orders")
            #expect(throws: Never.self) { try consoleHeader.inspect().find(text: "1 line") }
            #expect(throws: Never.self) { try hostedNetwork.body.inspect().find(text: "/v1/orders") }
            sut.close()
            socketServer.stop()
            storeServer.stop()
        }

        @Test("The kit's report holds the hosted Console's lines and Network's requests, under a summary naming the app")
        func reportOfTheHostedPlugins() async throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarHostingTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let app = App()
            app.consoleStore.ingest(Self.line)
            app.networkStore.recordStart(Self.request)
            let server = DebugDrawerAppGroupStoreServer(registry: app.registry, directory: store)
            server.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            try server.start()
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            var consoleTransport: DebugDrawerPluginTransport<ConsoleSnapshot, ConsoleCommand>?
            let console = DebugDrawerSidecarPlugin(
                id: ConsolePlugin().id, title: "Console", icon: "terminal", snapshot: ConsoleSnapshot.self, command: ConsoleCommand.self
            ) { transport in
                consoleTransport = transport
                return ConsolePlugin(transport: transport)
            }
            let sut = try DebugDrawerSidecarConnection(app: listed)
            _ = try await sut.host(console)
            _ = try await sut.host(.network)
            for await snapshot in try #require(consoleTransport).snapshots() where !snapshot.log.lines.isEmpty {
                break
            }
            let reports = store.deletingLastPathComponent().appending(path: "Reports")

            let archive = try sut.createReport(in: reports)
            let unzipped = reports.appending(path: "unzipped")
            let unzip = Process()
            unzip.executableURL = URL(filePath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", archive.path, unzipped.path]
            try unzip.run()
            unzip.waitUntilExit()
            let folder = try #require(try FileManager.default.contentsOfDirectory(at: unzipped, includingPropertiesForKeys: nil).first)
            let summary = try String(contentsOf: folder.appending(path: "summary.txt"), encoding: .utf8)
            let consoleText = try String(contentsOf: folder.appending(path: "Console/console.txt"), encoding: .utf8)
            let har = try String(contentsOf: folder.appending(path: "Network/network.har"), encoding: .utf8)

            #expect(archive.lastPathComponent.hasPrefix("Shop-Report-"))
            #expect(summary.contains("Bug report: Shop"))
            #expect(summary.contains("Bundle ID: com.example.shop"))
            #expect(summary.contains("Version: 2.4 (881)"))
            #expect(consoleText.contains("Order 1042 placed"))
            #expect(har.contains("https://api.example.com/v1/orders"))
            sut.close()
            server.stop()
        }

        @Test("The shipped plugins are the Console and Network plugins, by their IDs")
        func shippedPlugins() {
            let console = DebugDrawerSidecarPlugin.console
            let network = DebugDrawerSidecarPlugin.network

            #expect([console.id, console.title, console.icon] == [ConsolePlugin().id, "Console", "terminal"])
            #expect([network.id, network.title, network.icon] == [NetworkPlugin().id, "Network", "network"])
        }
    }
#endif
