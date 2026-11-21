// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    @testable import DebugDrawerNetworkPlugin
    @testable import DebugDrawerRemote
    import Foundation
    import Network
    import SwiftUI
    import Testing
    import ViewInspector

    // What the Mac viewer's window shows: NetworkPluginView and ConsolePluginView over a
    // DebugDrawerNetworkTransport paired with a device's server on 127.0.0.1, the device's models
    // real (their storage in memory). Hosted, as the views connect as they appear and redraw as
    // snapshots arrive; serialized, as hosts must not run at once. Each wait is for the event that
    // step produces: the connection's state, then the view's own transport's snapshot.
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct RemotePluginViewsTests {
        @Test("Paired on 127.0.0.1, NetworkPluginView and ConsolePluginView show a request and a log line the device records after they connect")
        func viewsShowDeviceLive() async throws {
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
            defer { server.stop() }
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let viewer = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Studio Mac")
            var shown: DebugDrawerPairingRequest?
            for await requests in server.$pairingRequests.values where !requests.isEmpty {
                shown = requests.first
                break
            }
            try await viewer.pair(code: try #require(shown).code)
            let request = NetworkEntry(
                timestamp: Date(timeIntervalSince1970: 1_800_000_000), method: "POST", url: "https://api.example.com/v1/orders",
                host: "api.example.com", path: "/v1/orders", requestHeaders: ["Content-Type": "application/json"],
                requestBody: Data(#"{"sku":"A1"}"#.utf8), statusCode: 201, duration: 0.12, isComplete: true
            )
            let line = LogLine(
                timestamp: Date(timeIntervalSince1970: 1_800_000_001), text: "Order 1042 placed", source: .sink, level: .info,
                subsystem: "com.example.shop", category: "checkout"
            )
            let networkView = NetworkPluginView(transport: viewer)
            let consoleView = ConsolePluginView(transport: viewer)
            let sut = HStack {
                networkView
                consoleView
            }
            var networkConnection: DebugDrawerPluginConnection<NetworkSnapshot, NetworkCommand>?
            var consoleConnection: DebugDrawerPluginConnection<ConsoleSnapshot, ConsoleCommand>?
            var rowsBefore: [String] = ["not read"]
            var linesBefore: [String] = ["not read"]
            var rowsAfter: [String] = []
            var linesAfter: [String] = []

            try await ViewHosting.host(sut) {
                try await networkView.inspection.inspect { view in
                    networkConnection = try view.actualView().connection
                }
                try await consoleView.inspection.inspect { view in
                    consoleConnection = try view.actualView().connection
                }
                var networkTransport: DebugDrawerPluginTransport<NetworkSnapshot, NetworkCommand>?
                for await state in try #require(networkConnection).$state.values {
                    if case let .connected(transport) = state {
                        networkTransport = transport
                        break
                    }
                }
                var consoleTransport: DebugDrawerPluginTransport<ConsoleSnapshot, ConsoleCommand>?
                for await state in try #require(consoleConnection).$state.values {
                    if case let .connected(transport) = state {
                        consoleTransport = transport
                        break
                    }
                }
                try await networkView.inspection.inspect { view in
                    rowsBefore = try view.findAll(NetworkRequestRow.self).map { try $0.actualView().entry.url }
                }
                try await consoleView.inspection.inspect { view in
                    linesBefore = try view.find(ConsoleTextView.self).actualView().lines.map(\.text)
                }

                networkStore.recordStart(request)
                for await snapshot in try #require(networkTransport).snapshots() where !snapshot.log.captured.isEmpty {
                    break
                }
                consoleStore.ingest(line)
                for await snapshot in try #require(consoleTransport).snapshots() where !snapshot.log.lines.isEmpty {
                    break
                }
                try await networkView.inspection.inspect { view in
                    rowsAfter = try view.findAll(NetworkRequestRow.self).map { try $0.actualView().entry.url }
                }
                try await consoleView.inspection.inspect { view in
                    linesAfter = try view.find(ConsoleTextView.self).actualView().lines.map(\.text)
                }
            }

            let expectedRows = ["https://api.example.com/v1/orders"]
            let expectedLines = ["Order 1042 placed"]
            #expect(rowsBefore.isEmpty)
            #expect(linesBefore.isEmpty)
            #expect(rowsAfter == expectedRows)
            #expect(linesAfter == expectedLines)
        }

        @Test("Until the app's model answers, NetworkPluginView and ConsolePluginView say they are waiting for it")
        func waitingForModel() async throws {
            let transport = UnansweredTransport()
            let networkView = NetworkPluginView(transport: transport)
            let consoleView = ConsolePluginView(transport: transport)
            let sut = HStack {
                networkView
                consoleView
            }
            var networkShown: String?
            var consoleShown: String?

            try await ViewHosting.host(sut) {
                try await networkView.inspection.inspect { view in
                    networkShown = try view.find(ViewType.ProgressView.self).labelView().text().string()
                }
                try await consoleView.inspection.inspect { view in
                    consoleShown = try view.find(ViewType.ProgressView.self).labelView().text().string()
                }
            }

            #expect(networkShown == "Waiting for Network…")
            #expect(consoleShown == "Waiting for Console…")
        }

        @Test("A connection that fails shows the plugin not reached and why, in place of the plugin")
        func failedConnection() async throws {
            let transport = UnansweredTransport(failure: .disconnected)
            let networkView = NetworkPluginView(transport: transport)
            let consoleView = ConsolePluginView(transport: transport)
            let sut = HStack {
                networkView
                consoleView
            }
            var networkConnection: DebugDrawerPluginConnection<NetworkSnapshot, NetworkCommand>?
            var consoleConnection: DebugDrawerPluginConnection<ConsoleSnapshot, ConsoleCommand>?
            var networkTexts: [String] = []
            var consoleTexts: [String] = []

            try await ViewHosting.host(sut) {
                try await networkView.inspection.inspect { view in
                    networkConnection = try view.actualView().connection
                }
                try await consoleView.inspection.inspect { view in
                    consoleConnection = try view.actualView().connection
                }
                for await state in try #require(networkConnection).$state.values {
                    if case .failed = state { break }
                }
                for await state in try #require(consoleConnection).$state.values {
                    if case .failed = state { break }
                }
                try await networkView.inspection.inspect { view in
                    networkTexts = try view.findAll(ViewType.Text.self).map { try $0.string() }
                }
                try await consoleView.inspection.inspect { view in
                    consoleTexts = try view.findAll(ViewType.Text.self).map { try $0.string() }
                }
            }

            let reason = DebugDrawerTransportError.disconnected.localizedDescription
            #expect(networkTexts == ["Network Not Reached", reason])
            #expect(consoleTexts == ["Console Not Reached", reason])
            #expect(Set(transport.asked) == [NetworkPlugin().id, ConsolePlugin().id])
        }
    }

    /// A connection whose models never answer, or that fails with `failure` at once; it lists the
    /// plugin IDs asked for.
    @MainActor
    private final class UnansweredTransport: DebugDrawerTransport {
        let failure: DebugDrawerTransportError?
        private(set) var asked: [String] = []
        /// Held, so the waits' streams never finish on their own.
        private var waits: [AsyncStream<Void>.Continuation] = []

        init(failure: DebugDrawerTransportError? = nil) {
            self.failure = failure
        }

        func connect<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable>(
            toPlugin pluginID: String,
            snapshot _: Snapshot.Type,
            command _: Command.Type
        ) async throws(DebugDrawerTransportError) -> DebugDrawerPluginTransport<Snapshot, Command> {
            asked.append(pluginID)
            if let failure { throw failure }
            // Never yields: waits until the task is cancelled, as the view goes.
            let (never, wait) = AsyncStream<Void>.makeStream()
            waits.append(wait)
            for await _ in never {}
            throw .cancelled
        }
    }
#endif
