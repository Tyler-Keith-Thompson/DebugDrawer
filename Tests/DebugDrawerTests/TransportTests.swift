#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation
    import Testing

    /// A model whose snapshot is a tally and a note, changed by commands.
    @MainActor
    private final class TallyModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var count = 0
            var note = ""
        }

        enum Command: Codable, Equatable, Sendable {
            case add(Int)
            case note(String)
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            switch command {
            case let .add(amount): snapshot.count += amount
            case let .note(text): snapshot.note = text
            }
        }
    }

    /// A model of other types, for connecting to with the wrong ones.
    @MainActor
    private final class FlagModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var isOn = false
        }

        enum Command: Codable, Sendable {
            case toggle
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            snapshot.isOn.toggle()
        }
    }

    // The transports' edges, each in this process: what a viewer sees when the model isn't there
    // yet, has other types, is replaced or goes, when the app's side stops, and when two viewers
    // reach one model over different transports at once. Socket paths are short ones in /tmp, as a
    // socket's address holds 103 bytes and the test's temporary directory can be longer.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct TransportTests {
        @Test("Two connections over different transports reach one model at once: each one's command shows on the other")
        func twoTransportsAtOnce() async throws {
            let model = TallyModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Tally")
            let socketPath = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            let directory = FileManager.default.temporaryDirectory.appending(path: "TransportTests-\(UUID().uuidString)")
            let socketServer = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            let storeServer = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
            try socketServer.start()
            try storeServer.start()
            let connections: [any DebugDrawerTransport] = try [
                DebugDrawerSocketTransport(socketPath: socketPath),
                DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            ]
            let overSocket = try await connections[0].connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            let overStore = try await connections[1].connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            let expected = TallyModel.Snapshot(count: 5, note: "from the store")

            overSocket.send(.add(5))
            for await snapshot in overStore.snapshots() where snapshot.count == 5 {
                break
            }
            overStore.send(.note("from the store"))
            for await snapshot in overSocket.snapshots() where snapshot == expected {
                break
            }

            #expect(model.snapshot == expected)
            #expect(overSocket.snapshot == expected)
            #expect(overStore.snapshot.count == 5)
            socketServer.stop()
            storeServer.stop()
        }

        @Test("A connect made before the model is registered waits, and returns its snapshot once it is")
        func connectWaitsForRegistration() async throws {
            let registry = DebugDrawerModelRegistry()
            let socketPath = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            let server = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            try server.start()
            let connection = try DebugDrawerSocketTransport(socketPath: socketPath)
            let model = TallyModel()
            model.perform(.add(3))

            async let connecting = connection.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            registry.register(model, id: "Tally")
            let actual = try await connecting.snapshot

            #expect(actual == TallyModel.Snapshot(count: 3))
            server.stop()
        }

        @Test("The in-process transport waits for registration too, and its command lands before send returns")
        func inProcessWaitsThenIsDirect() async throws {
            let registry = DebugDrawerModelRegistry()
            let sut = DebugDrawerInProcessTransport(registry: registry)
            let model = TallyModel()

            async let connecting = sut.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            registry.register(model, id: "Tally")
            let transport = try await connecting
            transport.send(.add(2))

            #expect(model.snapshot.count == 2)
            #expect(transport.snapshot.count == 2)
        }

        @Test("Connecting with types other than the model's throws mismatchedTypes, over every transport")
        func mismatchedTypes() async throws {
            let registry = DebugDrawerModelRegistry()
            registry.register(FlagModel(), id: "Flag")
            let socketPath = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            let directory = FileManager.default.temporaryDirectory.appending(path: "TransportTests-\(UUID().uuidString)")
            let socketServer = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            let storeServer = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
            try socketServer.start()
            try storeServer.start()
            let connections: [any DebugDrawerTransport] = try [
                DebugDrawerInProcessTransport(registry: registry),
                DebugDrawerSocketTransport(socketPath: socketPath),
                DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            ]

            for connection in connections {
                await #expect(throws: DebugDrawerTransportError.mismatchedTypes) {
                    try await connection.connect(toPlugin: "Flag", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
                }
            }
            socketServer.stop()
            storeServer.stop()
        }

        @Test("A connect waiting when the server stops throws disconnected, and the connection says it is closed")
        func serverStopDisconnects() async throws {
            let registry = DebugDrawerModelRegistry()
            let socketPath = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            let server = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            try server.start()
            let sut = try DebugDrawerSocketTransport(socketPath: socketPath)

            let connecting = Task {
                try await sut.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            }
            server.stop()
            let result = await connecting.result

            #expect(throws: DebugDrawerTransportError.disconnected) { try result.get() }
            #expect(!sut.isConnected)
        }

        @Test("When the server stops, isConnected turns false, the transport keeps its last snapshot and drops later commands")
        func lastSnapshotStays() async throws {
            let model = TallyModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Tally")
            let socketPath = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            let server = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            try server.start()
            let connection = try DebugDrawerSocketTransport(socketPath: socketPath)
            let sut = try await connection.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            let expected = TallyModel.Snapshot(count: 4)
            sut.send(.add(4))
            for await snapshot in sut.snapshots() where snapshot == expected {
                break
            }

            server.stop()
            for await isConnected in connection.$isConnected.values where !isConnected {
                break
            }
            sut.send(.add(100))
            try server.start()
            let reconnected = try DebugDrawerSocketTransport(socketPath: socketPath)
            let fresh = try await reconnected.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)

            #expect(sut.snapshot == expected)
            #expect(fresh.snapshot == expected)
            #expect(model.snapshot == expected)
            server.stop()
        }

        @Test("A model registered anew under an ID is what connected viewers see from then on")
        func reregistrationReplaces() async throws {
            let registry = DebugDrawerModelRegistry()
            registry.register(TallyModel(), id: "Tally")
            let socketPath = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            let server = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            try server.start()
            let connection = try DebugDrawerSocketTransport(socketPath: socketPath)
            let sut = try await connection.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            let replacement = TallyModel()
            replacement.perform(.note("replacement"))

            registry.register(replacement, id: "Tally")
            for await snapshot in sut.snapshots() where snapshot.note == "replacement" {
                break
            }
            sut.send(.add(1))
            for await snapshot in sut.snapshots() where snapshot.count == 1 {
                break
            }

            #expect(replacement.snapshot == TallyModel.Snapshot(count: 1, note: "replacement"))
            server.stop()
        }

        @Test("A command for a plugin no longer registered is dropped, and the server keeps serving the others")
        func commandAfterUnregisterDropped() async throws {
            let tally = TallyModel()
            let flag = FlagModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(tally, id: "Tally")
            registry.register(flag, id: "Flag")
            let socketPath = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            let server = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            try server.start()
            let connection = try DebugDrawerSocketTransport(socketPath: socketPath)
            let tallyTransport = try await connection.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            let flagTransport = try await connection.connect(toPlugin: "Flag", snapshot: FlagModel.Snapshot.self, command: FlagModel.Command.self)

            registry.unregister(id: "Tally")
            tallyTransport.send(.add(9))
            flagTransport.send(.toggle)
            for await snapshot in flagTransport.snapshots() where snapshot.isOn {
                break
            }

            #expect(tally.snapshot.count == 0)
            #expect(flag.snapshot.isOn)
            server.stop()
        }

        @Test("Nothing listening at the path throws unreachable; a path too long for a socket throws socketPathTooLong")
        func socketConnectFailures() {
            let missing = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            let tooLong = "/tmp/" + String(repeating: "x", count: 104)

            #expect(throws: DebugDrawerTransportError.unreachable) { try DebugDrawerSocketTransport(socketPath: missing) }
            #expect(throws: DebugDrawerTransportError.socketPathTooLong) { try DebugDrawerSocketTransport(socketPath: tooLong) }
            #expect(throws: DebugDrawerTransportError.socketPathTooLong) {
                try DebugDrawerSocketServer(registry: DebugDrawerModelRegistry(), socketPath: tooLong).start()
            }
        }

        @Test("A second server can't take a path a live one listens on; once the first stops, it can")
        func liveSocketIsNotReplaced() throws {
            let registry = DebugDrawerModelRegistry()
            let socketPath = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            let first = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            let second = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            try first.start()

            #expect(throws: DebugDrawerTransportError.cannotServe) { try second.start() }
            first.stop()
            try second.start()

            #expect(second.isRunning)
            #expect(!first.isRunning)
            second.stop()
        }

        @Test("A server takes the path of a socket left by a run that ended without stopping")
        func staleSocketIsReplaced() async throws {
            let model = TallyModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Tally")
            let socketPath = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            let stale = socket(AF_UNIX, SOCK_STREAM, 0)
            var address = sockaddr_un()
            address.sun_family = sa_family_t(AF_UNIX)
            withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: Array(socketPath.utf8)) }
            let bound = withUnsafePointer(to: address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(stale, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            close(stale)
            let server = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)

            try server.start()
            let connection = try DebugDrawerSocketTransport(socketPath: socketPath)
            let transport = try await connection.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)

            #expect(bound == 0)
            #expect(transport.snapshot == model.snapshot)
            server.stop()
        }

        @Test("A server won't take a path that holds a file other than a socket")
        func regularFileIsNotReplaced() throws {
            let path = "/tmp/dd-\(UUID().uuidString.prefix(8)).sock"
            try Data("keep me".utf8).write(to: URL(filePath: path))
            let sut = DebugDrawerSocketServer(registry: DebugDrawerModelRegistry(), socketPath: path)

            #expect(throws: DebugDrawerTransportError.cannotServe) { try sut.start() }
            #expect(try Data(contentsOf: URL(filePath: path)) == Data("keep me".utf8))
        }

        @Test("Commands left in the store while the app's server is stopped are performed, in order, when it starts")
        func storeCommandsWaitForTheApp() async throws {
            let model = TallyModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Tally")
            let directory = FileManager.default.temporaryDirectory.appending(path: "TransportTests-\(UUID().uuidString)")
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
            try server.start()
            let connection = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sut = try await connection.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            let expected = TallyModel.Snapshot(count: 3, note: "second")

            server.stop()
            sut.send(.add(1))
            sut.send(.note("first"))
            sut.send(.add(2))
            sut.send(.note("second"))
            let waiting = model.snapshot
            try server.start()
            for await snapshot in sut.snapshots() where snapshot == expected {
                break
            }

            #expect(waiting == TallyModel.Snapshot())
            #expect(model.snapshot == expected)
            server.stop()
        }

        @Test("A store viewer started after the app's server has stopped reads the last snapshot it wrote")
        func storeKeepsTheLastSnapshot() async throws {
            let model = TallyModel()
            model.perform(.add(7))
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Tally")
            let directory = FileManager.default.temporaryDirectory.appending(path: "TransportTests-\(UUID().uuidString)")
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)
            try server.start()
            let first = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            _ = try await first.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            server.stop()

            let later = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let actual = try await later.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)

            #expect(actual.snapshot == TallyModel.Snapshot(count: 7))
        }

        @Test("A store file that isn't a message, and a command file another build left, are skipped")
        func storeSkipsUnreadableFiles() async throws {
            let model = TallyModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Tally")
            let directory = FileManager.default.temporaryDirectory.appending(path: "TransportTests-\(UUID().uuidString)")
            let commands = AppGroupStoreLayout.appDirectory(inStore: directory).appending(path: "commands")
            let snapshots = AppGroupStoreLayout.appDirectory(inStore: directory).appending(path: "snapshots")
            try FileManager.default.createDirectory(at: commands, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: snapshots, withIntermediateDirectories: true)
            try Data("garbage".utf8).write(to: commands.appending(path: "0-garbage.json"))
            try Data("garbage".utf8).write(to: snapshots.appending(path: "Other.json"))
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: directory)

            try server.start()
            let connection = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sut = try await connection.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            sut.send(.add(1))
            for await snapshot in sut.snapshots() where snapshot.count == 1 {
                break
            }

            #expect(model.snapshot.count == 1)
            #expect(!FileManager.default.fileExists(atPath: commands.appending(path: "0-garbage.json").path))
            server.stop()
        }

        @Test("A cancelled connect throws cancelled")
        func cancelledConnect() async {
            let sut = DebugDrawerInProcessTransport(registry: DebugDrawerModelRegistry())

            let connecting = Task {
                try await sut.connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            }
            connecting.cancel()
            let result = await connecting.result

            #expect(throws: DebugDrawerTransportError.cancelled) { try result.get() }
        }
    }
#endif
