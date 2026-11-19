#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerRemote
    import Foundation
    import Network
    import Testing

    // The hello over the network transport, on the loopback interface as the pairing tests are: it
    // moves only once the device accepts, after the pairing messages, so a viewer reads it as core's
    // message rather than dropping it as a pairing one.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkVersioningTests {
        @Test("A paired viewer reads the device's hello: both agree on this build's version and every capability")
        func pairedViewerAgrees() async throws {
            let model = CounterModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Counter")
            let server = DebugDrawerNetworkServer(registry: registry, configuration: .loopback)
            try await server.start()
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let sut = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Studio Mac")
            var shown: DebugDrawerPairingRequest?
            for await requests in server.$pairingRequests.values where !requests.isEmpty {
                shown = requests.first
                break
            }
            let expected = TransportHello.current.agreement(with: .current)

            try await sut.pair(code: #require(shown).code)
            let counter = try await sut.connect(toPlugin: "Counter", snapshot: CounterModel.Snapshot.self, command: CounterModel.Command.self)
            counter.send(.add(3))
            for await snapshot in counter.snapshots() where snapshot.count == 3 {
                break
            }

            #expect(sut.models.peer.agreement == expected)
            #expect(model.snapshot.count == 3)
            server.stop()
        }
    }
#endif
