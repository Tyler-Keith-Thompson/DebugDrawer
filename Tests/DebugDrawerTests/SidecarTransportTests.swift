#if DEBUG
    import Combine
    @testable import DebugDrawer
    import Foundation
    import Testing

    /// A model that keeps every number a command brings, in the order performed, so a command
    /// performed twice, or out of order, shows.
    @MainActor
    private final class HistoryModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var history: [Int] = []
        }

        enum Command: Codable, Equatable, Sendable {
            case append(Int)
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            switch command {
            case let .append(number): snapshot.history.append(number)
            }
        }
    }

    // A sidecar and an app in one process, through the real socket and store servers over a
    // temporary "group container" whose path is longer than a socket's address holds, as the iOS
    // simulator's are. The app's socket is stopped and started to stand for it going to the
    // background and coming back; its store server stands for the files a suspended app leaves.
    // Each wait is for the event the step should produce (the channel changing, a snapshot), never
    // for time. The model records every number in the order performed, so a command lost,
    // performed twice, or out of order fails the history's equality.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarTransportTests {
        @Test("A socket whose path is longer than an address holds binds there, a viewer connects, and the working directory is left as it was")
        func longSocketPath() async throws {
            let container = FileManager.default.temporaryDirectory
                .appending(path: "SidecarTransportTests-\(UUID().uuidString)")
                .appending(path: String(repeating: "Shared-AppGroup-", count: 6))
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            let socketPath = container.appending(path: "drawer.sock").path
            let model = HistoryModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "History")
            let server = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            let workingDirectory = FileManager.default.currentDirectoryPath

            try server.start()
            let connection = try DebugDrawerSocketTransport(socketPath: socketPath)
            let sut = try await connection.connect(toPlugin: "History", snapshot: HistoryModel.Snapshot.self, command: HistoryModel.Command.self)
            sut.send(.append(1))
            for await snapshot in sut.snapshots() where snapshot.history == [1] {
                break
            }
            var status = stat()
            let found = lstat(socketPath, &status)
            server.stop()

            #expect(socketPath.utf8.count > UnixSocketAddress.maximumPathLength + 1)
            #expect(found == 0)
            #expect(status.st_mode & S_IFMT == S_IFSOCK)
            #expect(model.snapshot.history == [1])
            #expect(FileManager.default.currentDirectoryPath == workingDirectory)
            #expect(!FileManager.default.fileExists(atPath: socketPath))
        }

        @Test("When the app's socket goes, the sidecar reads the store; commands sent before, during and after land once, in order; it returns")
        func fallsBackAndReturns() async throws {
            let container = FileManager.default.temporaryDirectory
                .appending(path: "SidecarTransportTests-\(UUID().uuidString)")
                .appending(path: String(repeating: "Shared-AppGroup-", count: 6))
            let socketPath = container.appending(path: "drawer.sock").path
            let storeDirectory = container.appending(path: "DebugDrawer")
            let model = HistoryModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "History")
            let socketServer = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            let storeServer = DebugDrawerAppGroupStoreServer(registry: registry, directory: storeDirectory)
            try storeServer.start()
            try socketServer.start()
            let sut = try DebugDrawerSidecarTransport(socketPath: socketPath, storeDirectory: storeDirectory)
            for await channel in sut.$channel.values where channel == .socket {
                break
            }
            let plugin = try await sut.connect(toPlugin: "History", snapshot: HistoryModel.Snapshot.self, command: HistoryModel.Command.self)
            var channels: [DebugDrawerSidecarTransport.Channel] = [sut.channel]

            plugin.send(.append(1))
            plugin.send(.append(2))
            for await snapshot in plugin.snapshots() where snapshot.history == [1, 2] {
                break
            }
            // Sent, and the socket stopped, in one turn of the main actor: the app reads none of
            // them before its socket goes, so each is still unacknowledged.
            plugin.send(.append(3))
            plugin.send(.append(4))
            plugin.send(.append(5))
            socketServer.stop()
            for await channel in sut.$channel.values where channel == .store {
                break
            }
            channels.append(sut.channel)
            plugin.send(.append(6))
            plugin.send(.append(7))
            for await snapshot in plugin.snapshots() where snapshot.history.contains(7) {
                break
            }
            try socketServer.start()
            for await channel in sut.$channel.values where channel == .socket {
                break
            }
            channels.append(sut.channel)
            plugin.send(.append(8))
            for await snapshot in plugin.snapshots() where snapshot.history.contains(8) {
                break
            }

            #expect(channels == [.socket, .store, .socket])
            #expect(model.snapshot.history == Array(1 ... 8))
            #expect(plugin.snapshot.history == Array(1 ... 8))
            socketServer.stop()
            storeServer.stop()
        }

        @Test("Commands left in the store while the app was away go over its socket first when it comes back, in order, once")
        func storeCommandsMoveToTheSocket() async throws {
            let container = FileManager.default.temporaryDirectory
                .appending(path: "SidecarTransportTests-\(UUID().uuidString)")
                .appending(path: String(repeating: "Shared-AppGroup-", count: 6))
            let socketPath = container.appending(path: "drawer.sock").path
            let storeDirectory = container.appending(path: "DebugDrawer")
            let model = HistoryModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "History")
            let socketServer = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            let storeServer = DebugDrawerAppGroupStoreServer(registry: registry, directory: storeDirectory)
            try storeServer.start()
            let sut = try DebugDrawerSidecarTransport(socketPath: socketPath, storeDirectory: storeDirectory)
            let plugin = try await sut.connect(toPlugin: "History", snapshot: HistoryModel.Snapshot.self, command: HistoryModel.Command.self)
            storeServer.stop()
            let firstChannel = sut.channel

            plugin.send(.append(1))
            plugin.send(.append(2))
            let waiting = model.snapshot.history
            try socketServer.start()
            for await channel in sut.$channel.values where channel == .socket {
                break
            }
            plugin.send(.append(3))
            for await snapshot in plugin.snapshots() where snapshot.history.contains(3) {
                break
            }
            try storeServer.start()
            plugin.send(.append(4))
            for await snapshot in plugin.snapshots() where snapshot.history.contains(4) {
                break
            }
            let leftInStore = try FileManager.default.contentsOfDirectory(atPath: storeDirectory.appending(path: "commands").path)

            #expect(firstChannel == .store)
            #expect(waiting.isEmpty)
            #expect(model.snapshot.history == [1, 2, 3, 4])
            #expect(leftInStore.isEmpty)
            socketServer.stop()
            storeServer.stop()
        }

        @Test("A command the app performed over the socket, whose acknowledgement was lost, isn't performed again through the store")
        func performedOnceAcrossSessions() throws {
            let model = HistoryModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "History")
            var socketSent: [TransportMessage] = []
            let socketSession = RegistrySession(registry: registry, link: .stream) { socketSent.append($0) }
            let storeSession = RegistrySession(registry: registry, link: .store) { _ in }
            let id = UUID()
            let command = try TransportMessage(
                kind: .command, pluginID: "History", payload: TransportMessage.payload(HistoryModel.Command.append(1)), commandID: id
            )

            socketSession.receive(.hello(.current))
            socketSession.receive(command)
            socketSession.close()
            storeSession.receive(.hello(.current))
            storeSession.receive(command)

            #expect(model.snapshot.history == [1])
            #expect(socketSent.map(\.kind) == [.hello, .acknowledgement])
            #expect(socketSent.last?.commandID == id)
        }

        @Test("The app acknowledges commands only to a viewer that lists acknowledgements, and a command without an ID is performed each time")
        func acknowledgementsOnlyWhenBothHaveThem() throws {
            let model = HistoryModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "History")
            var sent: [TransportMessage] = []
            let sut = RegistrySession(registry: registry, link: .stream) { sent.append($0) }
            let withoutAcknowledgements = TransportHello(version: 2, oldestVersion: 1, capabilities: [.commands, .unsubscribe])
            let payload = try TransportMessage.payload(HistoryModel.Command.append(1))

            sut.receive(.hello(withoutAcknowledgements))
            sut.receive(TransportMessage(kind: .command, pluginID: "History", payload: payload, commandID: UUID()))
            sut.receive(TransportMessage(kind: .command, pluginID: "History", payload: payload))
            sut.receive(TransportMessage(kind: .command, pluginID: "History", payload: payload))
            sut.close()

            #expect(model.snapshot.history == [1, 1, 1])
            #expect(sent.map(\.kind) == [.hello])
        }

        @Test("A viewer keeps each command until the app acknowledges it, and none for an app that doesn't", arguments: [true, false])
        func viewerKeepsUnacknowledged(appAcknowledges: Bool) async throws {
            let appHello = appAcknowledges
                ? TransportHello.current
                : TransportHello(version: 2, oldestVersion: 1, capabilities: [.commands, .unsubscribe])
            let (inbox, delivered) = AsyncStream<TransportMessage>.makeStream()
            let sut = RemoteModels(link: .stream) { delivered.yield($0) }
            let snapshot = try TransportMessage.payload(HistoryModel.Snapshot())
            let app = Task { @MainActor in
                var commands: [TransportMessage] = []
                for await message in inbox {
                    if message.kind == .subscribe {
                        sut.receive(TransportMessage(kind: .snapshot, pluginID: message.pluginID, payload: snapshot))
                    }
                    if message.kind == .command { commands.append(message) }
                    if commands.count == 2 { break }
                }
                return commands
            }
            sut.receive(.hello(appHello))
            let plugin = try await sut.connect(
                toPlugin: "History", snapshot: HistoryModel.Snapshot.self, command: HistoryModel.Command.self, holding: sut
            )

            plugin.send(.append(1))
            plugin.send(.append(2))
            let commands = await app.value
            sut.receive(TransportMessage(kind: .acknowledgement, pluginID: "History", commandID: commands.first?.commandID))
            let expected = appAcknowledges ? Array(commands.dropFirst()) : []

            #expect(commands.count == 2)
            #expect(commands.allSatisfy { $0.commandID != nil })
            #expect(sut.unacknowledgedCommands == expected)
        }

        @Test("The sidecar reads the store while nothing listens on the socket, and a command waits there for the app")
        func storeWhileNoSocket() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "SidecarTransportTests-\(UUID().uuidString)")
            let storeDirectory = container.appending(path: "DebugDrawer")
            let model = HistoryModel()
            model.perform(.append(1))
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "History")
            let storeServer = DebugDrawerAppGroupStoreServer(registry: registry, directory: storeDirectory)
            try storeServer.start()
            let sut = try DebugDrawerSidecarTransport(socketPath: container.appending(path: "drawer.sock").path, storeDirectory: storeDirectory)
            let plugin = try await sut.connect(toPlugin: "History", snapshot: HistoryModel.Snapshot.self, command: HistoryModel.Command.self)
            storeServer.stop()

            plugin.send(.append(2))
            let waiting = model.snapshot.history
            try storeServer.start()
            for await snapshot in plugin.snapshots() where snapshot.history.contains(2) {
                break
            }

            #expect(sut.channel == .store)
            #expect(waiting == [1])
            #expect(model.snapshot.history == [1, 2])
            storeServer.stop()
        }

        @Test("A socket file name longer than an address holds throws socketPathTooLong from the sidecar too")
        func sidecarFileNameTooLong() {
            let directory = FileManager.default.temporaryDirectory.appending(path: "SidecarTransportTests-\(UUID().uuidString)")
            let socketPath = directory.appending(path: String(repeating: "x", count: UnixSocketAddress.maximumPathLength + 1)).path

            #expect(throws: DebugDrawerTransportError.socketPathTooLong) {
                try DebugDrawerSidecarTransport(socketPath: socketPath, storeDirectory: directory.appending(path: "DebugDrawer"))
            }
        }
    }
#endif
