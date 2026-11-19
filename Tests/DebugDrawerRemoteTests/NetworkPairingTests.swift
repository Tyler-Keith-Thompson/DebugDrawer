#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerRemote
    import Foundation
    import Network
    import Testing

    // Pairing over a real TCP connection on the loopback interface, 127.0.0.1, which no local
    // network permission covers: the server advertises nothing (`.loopback`), and the viewer
    // connects to the port the system gave it. Each wait is for the state the step should produce
    // (a request shown, the viewer's state, the end of a stream), so nothing waits on time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkPairingTests {
        @Test("A viewer that sends the code the device shows is paired, and reads and drives a model")
        func rightCodePairs() async throws {
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
            let request = try #require(shown)
            for await state in sut.$pairingState.values where state == .waitingForCode {
                break
            }
            let codeIsDigits = request.code.allSatisfy { $0.isASCII && $0.isNumber }

            try await sut.pair(code: request.code)
            let counter = try await sut.connect(toPlugin: "Counter", snapshot: CounterModel.Snapshot.self, command: CounterModel.Command.self)
            counter.send(.add(2))
            for await snapshot in counter.snapshots() where snapshot.count == 2 {
                break
            }

            #expect(request.viewerName == "Studio Mac")
            #expect(request.code.count == 6)
            #expect(codeIsDigits)
            #expect(sut.pairingState == .paired)
            #expect(server.pairingRequests.isEmpty)
            #expect(server.pairedViewers == [DebugDrawerPairedViewer(id: request.id, name: "Studio Mac")])
            #expect(model.snapshot.count == 2)
            server.stop()
        }

        @Test("A viewer the person rejects on the device is told so, disconnected, and never reaches a model")
        func rejectedViewer() async throws {
            let registry = DebugDrawerModelRegistry()
            registry.register(CounterModel(), id: "Counter")
            let server = DebugDrawerNetworkServer(registry: registry, configuration: .loopback)
            try await server.start()
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let sut = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Unknown Mac")
            var shown: DebugDrawerPairingRequest?
            for await requests in server.$pairingRequests.values where !requests.isEmpty {
                shown = requests.first
                break
            }
            let request = try #require(shown)

            server.reject(request)
            for await state in sut.$pairingState.values {
                if case .failed = state { break }
            }

            #expect(sut.pairingState == .failed(.rejected))
            await #expect(throws: DebugDrawerPairingError.rejected) { try await sut.pair(code: request.code) }
            await #expect(throws: DebugDrawerTransportError.disconnected) {
                _ = try await sut.connect(toPlugin: "Counter", snapshot: CounterModel.Snapshot.self, command: CounterModel.Command.self)
            }
            #expect(server.pairingRequests.isEmpty)
            #expect(server.pairedViewers.isEmpty)
            server.stop()
        }

        @Test("A viewer that sends a wrong code is refused for good: the request is gone and no model is reached")
        func wrongCodeIsRefused() async throws {
            let model = CounterModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Counter")
            let server = DebugDrawerNetworkServer(registry: registry, configuration: .loopback)
            try await server.start()
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let sut = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Guessing Mac")
            var shown: DebugDrawerPairingRequest?
            for await requests in server.$pairingRequests.values where !requests.isEmpty {
                shown = requests.first
                break
            }
            let request = try #require(shown)
            let wrongCode = request.code == "000000" ? "000001" : "000000"

            await #expect(throws: DebugDrawerPairingError.wrongCode) { try await sut.pair(code: wrongCode) }
            await #expect(throws: DebugDrawerPairingError.wrongCode) { try await sut.pair(code: request.code) }
            await #expect(throws: DebugDrawerTransportError.disconnected) {
                _ = try await sut.connect(toPlugin: "Counter", snapshot: CounterModel.Snapshot.self, command: CounterModel.Command.self)
            }

            #expect(server.pairingRequests.isEmpty)
            #expect(server.pairedViewers.isEmpty)
            server.stop()
        }

        @Test("A peer that skips pairing and asks for a model is closed without a byte of it")
        func unpairedPeerIsClosed() async throws {
            let registry = DebugDrawerModelRegistry()
            registry.register(CounterModel(), id: "Counter")
            let server = DebugDrawerNetworkServer(registry: registry, configuration: .loopback)
            try await server.start()
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let sut = NetworkConnection(NWConnection(to: .hostPort(host: "127.0.0.1", port: port), using: .tcp))
            let subscribe = Data(#"{"kind":"subscribe","payload":"","pluginID":"Counter","version":1}"#.utf8)

            sut.send(subscribe)
            var received: [Data] = []
            for await body in sut.frames {
                received.append(body)
            }

            #expect(received.isEmpty)
            #expect(server.pairingRequests.isEmpty)
            #expect(server.pairedViewers.isEmpty)
            server.stop()
        }

        @Test("A code sent before the pairing request closes the connection, unpaired")
        func codeBeforeRequestIsClosed() async throws {
            let server = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: .loopback)
            try await server.start()
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let sut = NetworkConnection(NWConnection(to: .hostPort(host: "127.0.0.1", port: port), using: .tcp))

            sut.send(PairingMessage(pairing: .code, code: "123456").encoded())
            var received: [Data] = []
            for await body in sut.frames {
                received.append(body)
            }

            #expect(received.isEmpty)
            #expect(server.pairedViewers.isEmpty)
            server.stop()
        }

        @Test("Beyond four requests shown at once, a viewer is turned away as busy")
        func busyDevice() async throws {
            let server = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: .loopback)
            try await server.start()
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let waiting = (1 ... 4).map { DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Mac \($0)") }
            for await requests in server.$pairingRequests.values where requests.count == 4 {
                break
            }

            let sut = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Mac 5")
            for await state in sut.$pairingState.values {
                if case .failed = state { break }
            }
            for viewer in waiting {
                for await state in viewer.$pairingState.values where state != .connecting {
                    break
                }
            }

            #expect(sut.pairingState == .failed(.rejected))
            #expect(server.pairingRequests.map(\.viewerName).sorted() == ["Mac 1", "Mac 2", "Mac 3", "Mac 4"])
            #expect(waiting.map(\.pairingState) == Array(repeating: .waitingForCode, count: 4))
            server.stop()
        }

        @Test("Stopping the server disconnects a paired viewer, which keeps its last snapshot")
        func stopDisconnects() async throws {
            let model = CounterModel()
            model.perform(.add(5))
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
            try await sut.pair(code: try #require(shown).code)
            let counter = try await sut.connect(toPlugin: "Counter", snapshot: CounterModel.Snapshot.self, command: CounterModel.Command.self)

            server.stop()
            for await state in sut.$pairingState.values {
                if case .failed = state { break }
            }

            #expect(sut.pairingState == .failed(.disconnected))
            #expect(counter.snapshot.count == 5)
            #expect(server.pairedViewers.isEmpty)
            #expect(server.isRunning == false)
        }

        @Test("A viewer pointed at a port nothing listens on fails as unreachable")
        func nothingListening() async throws {
            let server = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: .loopback)
            try await server.start()
            let port = try #require(server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            server.stop()

            let sut = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Studio Mac")
            for await state in sut.$pairingState.values {
                if case .failed = state { break }
            }

            #expect(sut.pairingState == .failed(.unreachable))
        }
    }
#endif
