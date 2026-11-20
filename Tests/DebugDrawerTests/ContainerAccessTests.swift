#if DEBUG
    import Darwin
    import DebugDrawer
    import Foundation
    import Testing

    /// A model whose snapshot counts the commands it performed.
    @MainActor
    private final class CountModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var count = 0
        }

        enum Command: Codable, Equatable, Sendable {
            case increment
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            snapshot.count += 1
        }
    }

    /// How a test takes access away from the store's directory, the way the sandbox, a declined
    /// macOS prompt or the files' modes would.
    enum StoreDenial: String, CaseIterable, Sendable {
        /// The container can't be searched, so the store's directory can't be made in it.
        case containerUnreadable
        /// The store's directory exists and can't be read.
        case storeUnreadable
        /// The store's directory exists and can't be written.
        case storeReadOnly
        /// The store's directories exist, and its commands directory can't be written.
        case commandsReadOnly
    }

    // What the socket and store servers and transports, and the sidecar transport, do when the
    // system refuses access to an app group's container: each fails closed, throwing accessDenied
    // (or, for a socket the sidecar can't connect to, publishing it), and writes nothing, in the
    // container or anywhere else. Access is taken away with the modes of a temporary directory the
    // test made, which the system refuses with EACCES as it refuses the sandbox's and a declined
    // prompt's with EPERM; each test gives the modes back as it ends. A missing container is a
    // resolver returning nil, as `containerURL` does where the entitlement lacks the group.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ContainerAccessTests {
        @Test("An app group the system gives no container throws noAppGroupContainer")
        func noContainer() {
            var asked: [String] = []
            func containerURL(_ identifier: String) -> URL? {
                asked.append(identifier)
                return nil
            }

            #expect(throws: DebugDrawerTransportError.noAppGroupContainer) {
                try DebugDrawerAppGroupContainer(groupIdentifier: "TEAMID.com.example.debug", containerURL: containerURL)
            }
            #expect(asked == ["TEAMID.com.example.debug"])
        }

        @Test("A group's container holds the store in DebugDrawer and each app's socket and files in DebugDrawer/apps/<bundle ID>")
        func containerPaths() throws {
            let container = URL(filePath: "/Users/someone/Library/Group Containers/TEAMID.com.example.debug", directoryHint: .isDirectory)
            let expectedStoreDirectory = "/Users/someone/Library/Group Containers/TEAMID.com.example.debug/DebugDrawer"
            let expectedShopDirectory = "/Users/someone/Library/Group Containers/TEAMID.com.example.debug/DebugDrawer/apps/com.example.shop"
            let expectedShopSocketPath = "\(expectedShopDirectory)/drawer.sock"
            let expectedOwnSocketPath = AppGroupStoreLayout.appDirectory(inStore: URL(filePath: expectedStoreDirectory, directoryHint: .isDirectory))
                .appending(path: "drawer.sock").path

            let sut = try DebugDrawerAppGroupContainer(groupIdentifier: "TEAMID.com.example.debug") { _ in container }

            #expect(sut.groupIdentifier == "TEAMID.com.example.debug")
            #expect(sut.url == container)
            #expect(sut.storeDirectory.path == expectedStoreDirectory)
            #expect(sut.appDirectory(of: "com.example.shop").path == expectedShopDirectory)
            #expect(sut.socketPath(of: "com.example.shop") == expectedShopSocketPath)
            #expect(sut.socketPath == expectedOwnSocketPath)
        }

        @Test("A bundle ID with a slash stays one directory under apps/, percent-encoded")
        func appDirectoryEncodesSlash() throws {
            let container = URL(filePath: "/tmp/group", directoryHint: .isDirectory)
            let expected = "/tmp/group/DebugDrawer/apps/..%2Fescape"

            let sut = try DebugDrawerAppGroupContainer(groupIdentifier: "TEAMID.com.example.debug") { _ in container }

            #expect(sut.appDirectory(of: "../escape").path == expected)
        }

        @Test("The store server throws accessDenied when its directory is refused, and writes nothing anywhere", arguments: StoreDenial.allCases)
        func storeServerDenied(_ denial: StoreDenial) throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "ContainerAccessTests-\(UUID().uuidString)")
            let container = root.appending(path: "container")
            let store = container.appending(path: "DebugDrawer")
            let app = AppGroupStoreLayout.appDirectory(inStore: store)
            let locked: URL
            let expectedFiles: [String]
            switch denial {
            case .containerUnreadable:
                try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
                locked = container
                expectedFiles = ["container"]
            case .storeUnreadable, .storeReadOnly:
                try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
                locked = store
                expectedFiles = ["container", "container/DebugDrawer"]
            case .commandsReadOnly:
                try FileManager.default.createDirectory(at: app.appending(path: "snapshots"), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: app.appending(path: "commands"), withIntermediateDirectories: true)
                locked = app.appending(path: "commands")
                let appPath = "container/DebugDrawer/apps/\(app.lastPathComponent)"
                expectedFiles = [
                    "container", "container/DebugDrawer", "container/DebugDrawer/apps", appPath, "\(appPath)/commands", "\(appPath)/snapshots"
                ]
            }
            chmod(locked.path, denial == .storeReadOnly || denial == .commandsReadOnly ? 0o555 : 0)
            defer { chmod(locked.path, 0o755) }
            let registry = DebugDrawerModelRegistry()
            registry.register(CountModel(), id: "Count")
            let sut = DebugDrawerAppGroupStoreServer(registry: registry, directory: store)

            #expect(throws: DebugDrawerTransportError.accessDenied) { try sut.start() }
            chmod(locked.path, 0o755)
            let actual = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()

            #expect(!sut.isRunning)
            #expect(actual == expectedFiles)
        }

        @Test("The store viewer throws accessDenied when its directory is refused, and writes nothing anywhere", arguments: StoreDenial.allCases)
        func storeTransportDenied(_ denial: StoreDenial) throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "ContainerAccessTests-\(UUID().uuidString)")
            let container = root.appending(path: "container")
            let store = container.appending(path: "DebugDrawer")
            let app = AppGroupStoreLayout.appDirectory(inStore: store)
            let locked: URL
            let expectedFiles: [String]
            switch denial {
            case .containerUnreadable:
                try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
                locked = container
                expectedFiles = ["container"]
            case .storeUnreadable, .storeReadOnly:
                try FileManager.default.createDirectory(at: store, withIntermediateDirectories: true)
                locked = store
                expectedFiles = ["container", "container/DebugDrawer"]
            case .commandsReadOnly:
                try FileManager.default.createDirectory(at: app.appending(path: "snapshots"), withIntermediateDirectories: true)
                try FileManager.default.createDirectory(at: app.appending(path: "commands"), withIntermediateDirectories: true)
                locked = app.appending(path: "commands")
                let appPath = "container/DebugDrawer/apps/\(app.lastPathComponent)"
                expectedFiles = [
                    "container", "container/DebugDrawer", "container/DebugDrawer/apps", appPath, "\(appPath)/commands", "\(appPath)/snapshots"
                ]
            }
            chmod(locked.path, denial == .storeReadOnly || denial == .commandsReadOnly ? 0o555 : 0)
            defer { chmod(locked.path, 0o755) }

            #expect(throws: DebugDrawerTransportError.accessDenied) { try DebugDrawerAppGroupStoreTransport(directory: app) }
            chmod(locked.path, 0o755)
            let actual = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()

            #expect(actual == expectedFiles)
        }

        @Test(
            "The socket server throws accessDenied when the socket's directory, or the container it would be made in, is refused, and makes nothing",
            arguments: [true, false]
        )
        func socketServerDenied(directoryExists: Bool) throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "ContainerAccessTests-\(UUID().uuidString)")
            let container = root.appending(path: "container")
            let socketDirectory = container.appending(path: "DebugDrawer")
            let locked = directoryExists ? socketDirectory : container
            try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
            chmod(locked.path, 0)
            defer { chmod(locked.path, 0o755) }
            let expectedFiles = directoryExists ? ["container", "container/DebugDrawer"] : ["container"]
            let sut = DebugDrawerSocketServer(registry: DebugDrawerModelRegistry(), socketPath: socketDirectory.appending(path: "drawer.sock").path)

            #expect(throws: DebugDrawerTransportError.accessDenied) { try sut.start() }
            chmod(locked.path, 0o755)
            let actual = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()

            #expect(!sut.isRunning)
            #expect(actual == expectedFiles)
        }

        @Test("A viewer refused the socket throws accessDenied, not unreachable, whether the socket or its directory is refused")
        func socketTransportDenied() throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "ContainerAccessTests-\(UUID().uuidString)")
            let socketPath = root.appending(path: "drawer.sock").path
            let server = DebugDrawerSocketServer(registry: DebugDrawerModelRegistry(), socketPath: socketPath)
            try server.start()
            defer { server.stop() }

            chmod(socketPath, 0)
            #expect(throws: DebugDrawerTransportError.accessDenied) { try DebugDrawerSocketTransport(socketPath: socketPath) }
            chmod(socketPath, 0o755)
            chmod(root.path, 0)
            #expect(throws: DebugDrawerTransportError.accessDenied) { try DebugDrawerSocketTransport(socketPath: socketPath) }
            chmod(root.path, 0o755)

            #expect(server.isRunning)
        }

        @Test("The sidecar throws accessDenied when the container is refused, and writes nothing anywhere")
        func sidecarDenied() throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "ContainerAccessTests-\(UUID().uuidString)")
            let container = root.appending(path: "container")
            try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
            chmod(container.path, 0)
            defer { chmod(container.path, 0o755) }
            let group = try DebugDrawerAppGroupContainer(groupIdentifier: "TEAMID.com.example.debug") { _ in container }
            let expectedFiles = ["container"]

            #expect(throws: DebugDrawerTransportError.accessDenied) {
                try DebugDrawerSidecarTransport(
                    socketPath: group.socketPath(of: "com.example.shop"), storeDirectory: group.appDirectory(of: "com.example.shop")
                )
            }
            chmod(container.path, 0o755)
            let actual = try FileManager.default.subpathsOfDirectory(atPath: root.path).sorted()

            #expect(actual == expectedFiles)
        }

        @Test("A sidecar refused the app's socket publishes accessDenied, works through the store meanwhile, and clears it once a socket answers")
        func sidecarSocketDenied() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "ContainerAccessTests-\(UUID().uuidString)")
            let group = try DebugDrawerAppGroupContainer(groupIdentifier: "TEAMID.com.example.debug") { _ in root }
            let model = CountModel()
            let registry = DebugDrawerModelRegistry()
            registry.register(model, id: "Count")
            let storeServer = DebugDrawerAppGroupStoreServer(registry: registry, directory: group.storeDirectory)
            let socketServer = DebugDrawerSocketServer(registry: registry, socketPath: group.socketPath)
            try storeServer.start()
            try socketServer.start()
            defer {
                socketServer.stop()
                storeServer.stop()
            }
            chmod(group.socketPath, 0)

            let sut = try DebugDrawerSidecarTransport(socketPath: group.socketPath, storeDirectory: storeServer.appDirectory)
            let deniedError = sut.socketError
            let deniedChannel = sut.channel
            let plugin = try await sut.connect(toPlugin: "Count", snapshot: CountModel.Snapshot.self, command: CountModel.Command.self)
            plugin.send(.increment)
            for await snapshot in plugin.snapshots() where snapshot.count == 1 {
                break
            }
            socketServer.stop()
            try socketServer.start()
            for await channel in sut.$channel.values where channel == .socket {
                break
            }

            #expect(deniedError == .accessDenied)
            #expect(deniedChannel == .store)
            #expect(model.snapshot.count == 1)
            #expect(sut.socketError == nil)
        }

        @Test("accessDenied and noAppGroupContainer say what to fix")
        func messages() {
            let expectedAccessDenied = """
            Access to the app group's container was denied. Add the group to both apps' \
            com.apple.security.application-groups entitlement and sign both with the same team; on macOS, prefix the group \
            with the team ID or list it in a provisioning profile, and if macOS asked whether this app may access data from \
            other apps and was told no, run tccutil reset SystemPolicyAppData <bundle ID> and allow it when asked again.
            """
            let expectedNoContainer = """
            The system gave no container for the app group. Add the group to this app's \
            com.apple.security.application-groups entitlement and sign the app with it.
            """

            let accessDenied = DebugDrawerTransportError.accessDenied.localizedDescription
            let noContainer = DebugDrawerTransportError.noAppGroupContainer.localizedDescription

            #expect(accessDenied == expectedAccessDenied)
            #expect(noContainer == expectedNoContainer)
        }
    }
#endif
