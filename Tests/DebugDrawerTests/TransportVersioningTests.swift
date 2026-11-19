#if DEBUG
    import Combine
    @testable import DebugDrawer
    import Foundation
    import Testing

    /// A model whose snapshot is a count, changed by commands.
    @MainActor
    private final class CountModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var count = 0
        }

        enum Command: Codable, Equatable, Sendable {
            case add(Int)
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            switch command {
            case let .add(amount): snapshot.count += amount
            }
        }
    }

    // Each side of a connection against a peer of another protocol version, in memory: the real
    // `RemoteModels` (a viewer) or `RegistrySession` (an app) on one end, and on the other a peer
    // the test plays by hand, whose messages it sends and whose inbox is a stream. A peer one major
    // version ahead or behind connects and only the capabilities both list are used; two apart
    // fail. A version 1 peer is one that never says hello. Where a test checks that something was
    // not sent, it first makes a round trip through the peer (a second plugin's subscribe and
    // snapshot), which runs every main-actor job queued before it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct TransportVersioningTests {
        @Test("A viewer connects to an app one major version ahead and uses only the capabilities both list")
        func viewerWithAppAhead() async throws {
            let current = TransportHello.current
            let ahead = TransportHello(
                version: current.version + 1,
                oldestVersion: current.version,
                capabilities: [.commands, .unsubscribe, TransportCapability(rawValue: "deltaSnapshots")]
            )
            let (inbox, delivered) = AsyncStream<TransportMessage>.makeStream()
            let sut = RemoteModels(link: .stream) { delivered.yield($0) }
            let snapshot = try TransportMessage.payload(CountModel.Snapshot(count: 1))
            let app = Task { @MainActor in
                var received: [TransportMessage] = []
                for await message in inbox {
                    received.append(message)
                    if message.kind == .subscribe {
                        sut.receive(TransportMessage(kind: .snapshot, pluginID: message.pluginID, payload: snapshot))
                    }
                    if message.kind == .unsubscribe { break }
                }
                return received
            }
            let expectedAgreement = TransportAgreement(version: current.version, capabilities: [.commands, .unsubscribe])
            let expectedKinds: [TransportMessage.Kind] = [.hello, .subscribe, .command, .unsubscribe]

            sut.receive(.hello(ahead))
            var count: DebugDrawerPluginTransport<CountModel.Snapshot, CountModel.Command>? = try await sut.connect(
                toPlugin: "Count", snapshot: CountModel.Snapshot.self, command: CountModel.Command.self, holding: sut
            )
            count?.send(.add(2))
            count = nil
            let received = await app.value

            let saidHello = try JSONDecoder().decode(TransportHello.self, from: received[0].payload)
            #expect(sut.peer.agreement == expectedAgreement)
            #expect(received.map(\.kind) == expectedKinds)
            #expect(saidHello == current)
        }

        @Test("A viewer connects to an app one major version behind and sends nothing that version lacks", arguments: [
            nil,
            TransportHello(version: TransportHello.current.version - 1, oldestVersion: TransportHello.current.version - 2, capabilities: [.commands])
        ] as [TransportHello?])
        func viewerWithAppBehind(appHello: TransportHello?) async throws {
            let (inbox, delivered) = AsyncStream<TransportMessage>.makeStream()
            let sut = RemoteModels(link: .stream) { delivered.yield($0) }
            let snapshot = try TransportMessage.payload(CountModel.Snapshot(count: 1))
            let app = Task { @MainActor in
                var received: [TransportMessage] = []
                for await message in inbox {
                    received.append(message)
                    if message.kind == .subscribe {
                        sut.receive(TransportMessage(kind: .snapshot, pluginID: message.pluginID, payload: snapshot))
                    }
                }
                return received
            }
            let expectedAgreement = TransportAgreement(version: TransportHello.current.version - 1, capabilities: [.commands])
            let expectedKinds: [TransportMessage.Kind] = [.hello, .subscribe, .command, .subscribe]

            if let appHello { sut.receive(.hello(appHello)) }
            var count: DebugDrawerPluginTransport<CountModel.Snapshot, CountModel.Command>? = try await sut.connect(
                toPlugin: "Count", snapshot: CountModel.Snapshot.self, command: CountModel.Command.self, holding: sut
            )
            count?.send(.add(2))
            count = nil
            _ = try await sut.connect(toPlugin: "Other", snapshot: CountModel.Snapshot.self, command: CountModel.Command.self, holding: sut)
            delivered.finish()
            let received = await app.value

            #expect(sut.peer.agreement == expectedAgreement)
            #expect(received.map(\.kind) == expectedKinds)
            #expect(received.map(\.pluginID) == ["", "Count", "Count", "Other"])
        }

        @Test("An app serves a viewer one major version ahead and stops a plugin it unsubscribes from")
        func appWithViewerAhead() async throws {
            let current = TransportHello.current
            let ahead = TransportHello(
                version: current.version + 1,
                oldestVersion: current.version,
                capabilities: [.commands, .unsubscribe, TransportCapability(rawValue: "deltaSnapshots")]
            )
            let model = CountModel()
            let other = CountModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Count")
            registry.register(other, id: "Other")
            let (outbox, sent) = AsyncStream<TransportMessage>.makeStream()
            let sut = RegistrySession(registry: registry, link: .stream) { sent.yield($0) }
            var viewer = outbox.makeAsyncIterator()
            let expectedAgreement = TransportAgreement(version: current.version, capabilities: [.commands, .unsubscribe])

            sut.receive(.hello(ahead))
            sut.receive(TransportMessage(kind: .subscribe, pluginID: "Count"))
            try sut.receive(TransportMessage(kind: .command, pluginID: "Count", payload: TransportMessage.payload(CountModel.Command.add(2))))
            var received: [TransportMessage] = []
            while let message = await viewer.next() {
                received.append(message)
                if message.kind == .snapshot, try JSONDecoder().decode(CountModel.Snapshot.self, from: message.payload).count == 2 { break }
            }
            sut.receive(TransportMessage(kind: .unsubscribe, pluginID: "Count"))
            model.perform(.add(40))
            sut.receive(TransportMessage(kind: .subscribe, pluginID: "Other"))
            while let message = await viewer.next() {
                received.append(message)
                if message.pluginID == "Other" { break }
            }
            sut.close()

            let countSnapshots = try received.filter { $0.pluginID == "Count" }
                .map { try JSONDecoder().decode(CountModel.Snapshot.self, from: $0.payload).count }
            #expect(sut.peer.agreement == expectedAgreement)
            #expect(received.first?.kind == .hello)
            #expect(model.snapshot.count == 42)
            #expect(countSnapshots.last == 2)
            #expect(!countSnapshots.contains(42))
        }

        @Test("An app serves a viewer one major version behind: it reads snapshots and its commands land", arguments: [
            nil,
            TransportHello(version: TransportHello.current.version - 1, oldestVersion: TransportHello.current.version - 2, capabilities: [.commands])
        ] as [TransportHello?])
        func appWithViewerBehind(viewerHello: TransportHello?) async throws {
            let model = CountModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Count")
            let (outbox, sent) = AsyncStream<TransportMessage>.makeStream()
            let sut = RegistrySession(registry: registry, link: .stream) { sent.yield($0) }
            let expectedAgreement = TransportAgreement(version: TransportHello.current.version - 1, capabilities: [.commands])

            if let viewerHello { sut.receive(.hello(viewerHello)) }
            sut.receive(TransportMessage(kind: .subscribe, pluginID: "Count"))
            try sut.receive(TransportMessage(kind: .command, pluginID: "Count", payload: TransportMessage.payload(CountModel.Command.add(3))))
            var received: [TransportMessage] = []
            for await message in outbox {
                received.append(message)
                if message.kind == .snapshot, try JSONDecoder().decode(CountModel.Snapshot.self, from: message.payload).count == 3 { break }
            }
            sut.close()

            #expect(sut.peer.agreement == expectedAgreement)
            #expect(model.snapshot.count == 3)
            #expect(received.first?.kind == .hello)
            #expect(received.last?.pluginID == "Count")
        }

        @Test("A viewer and an app two major versions apart don't connect: connects throw incompatibleVersion and the connection is closed")
        func twoVersionsApart() async throws {
            let current = TransportHello.current
            let twoAhead = TransportHello(version: current.version + 2, oldestVersion: current.version + 1, capabilities: [.commands])
            let twoBehind = TransportHello(version: current.version - 2, oldestVersion: current.version - 2, capabilities: [.commands])
            let registry = DebugDrawerModelRegistry()
            registry.register(CountModel(), id: "Count")
            var disconnects: [String] = []
            var appSent: [TransportMessage] = []
            let viewer = RemoteModels(link: .stream) { _ in } disconnect: { disconnects.append("viewer") }
            let app = RegistrySession(registry: registry, link: .stream) { appSent.append($0) } disconnect: { disconnects.append("app") }

            viewer.receive(.hello(twoAhead))
            app.receive(.hello(twoBehind))
            app.receive(TransportMessage(kind: .subscribe, pluginID: "Count"))

            await #expect(throws: DebugDrawerTransportError.incompatibleVersion) {
                _ = try await viewer.connect(toPlugin: "Count", snapshot: CountModel.Snapshot.self, command: CountModel.Command.self, holding: viewer)
            }
            #expect(disconnects == ["viewer", "app"])
            #expect(viewer.peer.agreement == nil)
            #expect(app.peer.agreement == nil)
            #expect(appSent.map(\.kind) == [.hello])
        }

        @Test("A connect waiting when the app's hello turns out incompatible throws incompatibleVersion")
        func waitingConnectLearnsIncompatibility() async throws {
            let current = TransportHello.current
            let twoAhead = TransportHello(version: current.version + 2, oldestVersion: current.version + 2, capabilities: [])
            let (inbox, delivered) = AsyncStream<TransportMessage>.makeStream()
            let sut = RemoteModels(link: .stream) { delivered.yield($0) }
            let app = Task { @MainActor in
                for await message in inbox where message.kind == .subscribe {
                    sut.receive(.hello(twoAhead))
                    break
                }
            }

            await #expect(throws: DebugDrawerTransportError.incompatibleVersion) {
                _ = try await sut.connect(toPlugin: "Count", snapshot: CountModel.Snapshot.self, command: CountModel.Command.self, holding: sut)
            }
            await app.value
        }

        @Test("A command to an app that doesn't list the commands capability is dropped, and its snapshots still arrive")
        func commandsOnlyWhenBothHaveThem() async throws {
            let current = TransportHello.current
            let readOnly = TransportHello(version: current.version + 1, oldestVersion: current.version, capabilities: [])
            let (inbox, delivered) = AsyncStream<TransportMessage>.makeStream()
            let sut = RemoteModels(link: .stream) { delivered.yield($0) }
            let first = try TransportMessage.payload(CountModel.Snapshot(count: 1))
            let app = Task { @MainActor in
                var received: [TransportMessage] = []
                for await message in inbox {
                    received.append(message)
                    if message.kind == .subscribe {
                        sut.receive(TransportMessage(kind: .snapshot, pluginID: message.pluginID, payload: first))
                    }
                }
                return received
            }

            sut.receive(.hello(readOnly))
            let count = try await sut.connect(toPlugin: "Count", snapshot: CountModel.Snapshot.self, command: CountModel.Command.self, holding: sut)
            count.send(.add(2))
            delivered.finish()
            let received = await app.value

            let expectedKinds: [TransportMessage.Kind] = [.hello, .subscribe]
            #expect(received.map(\.kind) == expectedKinds)
            #expect(sut.peer.agreement == TransportAgreement(version: current.version, capabilities: []))
            #expect(count.snapshot == CountModel.Snapshot(count: 1))
        }

        @Test("Over the socket, a version 1 viewer that never says hello reads a snapshot and its command lands")
        func versionOneViewerOverTheSocket() async throws {
            let model = CountModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Count")
            let socketPath = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            let server = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            try server.start()
            let sut = try SocketConnection(descriptor: #require(UnixSocketAddress.connect(to: socketPath)))
            let subscribe = Data(#"{"kind":"subscribe","payload":"","pluginID":"Count","version":1}"#.utf8)
            let command = try TransportMessage(kind: .command, pluginID: "Count", payload: TransportMessage.payload(CountModel.Command.add(4)))

            try sut.send(#require(TransportMessage.decoded(from: subscribe)))
            sut.send(command)
            var received: [TransportMessage] = []
            for await message in sut.messages {
                received.append(message)
                if message.kind == .snapshot, try JSONDecoder().decode(CountModel.Snapshot.self, from: message.payload).count == 4 { break }
            }
            sut.close()

            #expect(received.first?.kind == .hello)
            #expect(model.snapshot.count == 4)
            server.stop()
        }

        @Test("Over the socket, a viewer two major versions ahead reads the app's hello, then the end of the stream")
        func incompatibleViewerOverTheSocket() async throws {
            let registry = DebugDrawerModelRegistry()
            registry.register(CountModel(), id: "Count")
            let socketPath = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            let server = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            try server.start()
            let sut = try SocketConnection(descriptor: #require(UnixSocketAddress.connect(to: socketPath)))
            let current = TransportHello.current
            let twoAhead = TransportHello(version: current.version + 2, oldestVersion: current.version + 2, capabilities: [.commands])

            sut.send(.hello(twoAhead))
            sut.send(TransportMessage(kind: .subscribe, pluginID: "Count"))
            var received: [TransportMessage] = []
            for await message in sut.messages {
                received.append(message)
            }

            let saidHello = try JSONDecoder().decode(TransportHello.self, from: #require(received.first).payload)
            #expect(received.map(\.kind) == [.hello])
            #expect(saidHello == current)
            server.stop()
        }

        @Test("Two sides agree on the lower version when each still speaks it, from either side; two major versions apart they don't")
        func agreementTable() {
            let sut = TransportHello(version: 2, oldestVersion: 1, capabilities: [.commands, .unsubscribe])
            let peers: [(hello: TransportHello, expected: Int?)] = [
                (TransportHello(version: 2, oldestVersion: 1, capabilities: [.commands, .unsubscribe]), 2),
                (TransportHello(version: 3, oldestVersion: 2, capabilities: [.commands]), 2),
                (TransportHello(version: 1, oldestVersion: 1, capabilities: [.commands]), 1),
                (TransportHello(version: 1, oldestVersion: 0, capabilities: [.commands]), 1),
                (TransportHello(version: 4, oldestVersion: 3, capabilities: [.commands]), nil),
                (TransportHello(version: 3, oldestVersion: 3, capabilities: [.commands]), nil),
                (TransportHello(version: 0, oldestVersion: 0, capabilities: [.commands]), nil)
            ]

            for peer in peers {
                let actual = sut.agreement(with: peer.hello)
                let reverse = peer.hello.agreement(with: sut)

                #expect(actual?.version == peer.expected, "\(peer.hello)")
                #expect(reverse == actual, "\(peer.hello)")
            }
            #expect(sut.agreement(with: sut)?.capabilities == [.commands, .unsubscribe])
            #expect(TransportHello.current == sut)
            #expect(TransportHello.firstVersion == TransportHello(version: 1, oldestVersion: 1, capabilities: [.commands]))
        }
    }
#endif
