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

    // A message of a kind this build doesn't know, as a newer peer would send: each end drops it,
    // logs its kind the first time (the log is written exactly when the kind joins the peer's
    // `ignoredKinds`), and goes on with the messages after it.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct TransportUnknownKindTests {
        @Test("A kind this build doesn't know decodes by its name and encodes back to it")
        func unknownKindRoundTrips() throws {
            let json = Data(#"{"kind":"shout","payload":"","pluginID":"Count","version":1}"#.utf8)

            let actual = try #require(TransportMessage.decoded(from: json))

            #expect(actual.kind == .unknown("shout"))
            #expect(try actual.encoded() == json)
        }

        @Test("Each unknown kind is remembered for its log the first time only, and at most 32 kinds are")
        func peerLogsEachKindOnce() {
            var sut = TransportPeer()
            let shout = TransportMessage(kind: .unknown("shout"), pluginID: "Count")
            let whisper = TransportMessage(kind: .unknown("whisper"), pluginID: "Count")

            let admissions = [sut.admit(shout), sut.admit(shout), sut.admit(whisper)]
            let afterThree = sut.ignoredKinds
            for index in 0 ..< 40 {
                _ = sut.admit(TransportMessage(kind: .unknown("kind\(index)"), pluginID: ""))
            }

            #expect(admissions == [.ignored, .ignored, .ignored])
            #expect(afterThree == ["shout", "whisper"])
            #expect(sut.ignoredKinds.count == TransportPeer.maximumIgnoredKinds)
            #expect(TransportPeer.maximumIgnoredKinds == 32)
        }

        @Test("A hello that doesn't decode is dropped, and the peer is still taken for version 1")
        func malformedHelloIsIgnored() {
            var sut = TransportPeer()

            let actual = sut.admit(TransportMessage(kind: .hello, pluginID: "", payload: Data("nonsense".utf8)))

            #expect(actual == .ignored)
            #expect(sut.agreement == TransportAgreement(version: 1, capabilities: [.commands]))
        }

        @Test("The app drops an unknown kind, remembers it once, and goes on serving the viewer")
        func appDropsUnknownKinds() async throws {
            let model = CountModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Count")
            let (outbox, sent) = AsyncStream<TransportMessage>.makeStream()
            let sut = RegistrySession(registry: registry, link: .stream) { sent.yield($0) }
            let shout = TransportMessage(kind: .unknown("shout"), pluginID: "Count", payload: Data("{}".utf8))

            sut.receive(.hello(.current))
            sut.receive(shout)
            sut.receive(shout)
            sut.receive(TransportMessage(kind: .subscribe, pluginID: "Count"))
            try sut.receive(TransportMessage(kind: .command, pluginID: "Count", payload: TransportMessage.payload(CountModel.Command.add(1))))
            var received: [TransportMessage] = []
            for await message in outbox {
                received.append(message)
                if message.kind == .snapshot { break }
            }
            sut.close()

            let expectedKinds: [TransportMessage.Kind] = [.hello, .snapshot]
            #expect(sut.peer.ignoredKinds == ["shout"])
            #expect(received.map(\.kind) == expectedKinds)
            #expect(model.snapshot.count == 1)
        }

        @Test("A viewer drops an unknown kind, remembers it once, and its connects still work")
        func viewerDropsUnknownKinds() async throws {
            let (inbox, delivered) = AsyncStream<TransportMessage>.makeStream()
            let sut = RemoteModels(link: .stream) { delivered.yield($0) }
            let snapshot = try TransportMessage.payload(CountModel.Snapshot(count: 7))
            let shout = TransportMessage(kind: .unknown("shout"), pluginID: "Count", payload: snapshot)
            let app = Task { @MainActor in
                for await message in inbox where message.kind == .subscribe {
                    sut.receive(shout)
                    sut.receive(shout)
                    sut.receive(TransportMessage(kind: .snapshot, pluginID: message.pluginID, payload: snapshot))
                    break
                }
            }

            let actual = try await sut.connect(toPlugin: "Count", snapshot: CountModel.Snapshot.self, command: CountModel.Command.self, holding: sut)
            await app.value

            #expect(actual.snapshot == CountModel.Snapshot(count: 7))
            #expect(sut.peer.ignoredKinds == ["shout"])
            #expect(!sut.isClosed)
        }

        @Test("Over the socket, unknown kinds sent to the app leave the connection up: the viewer's subscribe and command after them are served")
        func socketStaysUp() async throws {
            let model = CountModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Count")
            let socketPath = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            let server = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            try server.start()
            let sut = try SocketConnection(descriptor: #require(UnixSocketAddress.connect(to: socketPath)))

            sut.send(.hello(.current))
            sut.send(TransportMessage(kind: .unknown("shout"), pluginID: "Count"))
            sut.send(TransportMessage(kind: .unknown("shout"), pluginID: "Count"))
            sut.send(TransportMessage(kind: .subscribe, pluginID: "Count"))
            try sut.send(TransportMessage(kind: .command, pluginID: "Count", payload: TransportMessage.payload(CountModel.Command.add(5))))
            var received: [TransportMessage] = []
            for await message in sut.messages {
                received.append(message)
                if message.kind == .snapshot, try JSONDecoder().decode(CountModel.Snapshot.self, from: message.payload).count == 5 { break }
            }
            sut.close()

            #expect(received.first?.kind == .hello)
            #expect(model.snapshot.count == 5)
            server.stop()
        }
    }
#endif
