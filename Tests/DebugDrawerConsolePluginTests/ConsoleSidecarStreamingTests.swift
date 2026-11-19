#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerConsolePlugin
    import Foundation
    import Testing

    // A sidecar app watching the host's console as it logs: the host's real Console model (its
    // mutes in memory) served by the real socket and store servers in a temporary "group
    // container" whose path is longer than a socket's address holds, as the iOS simulator's are,
    // and a `DebugDrawerSidecarTransport` reading it. Each line is logged only after the one before
    // has reached the sidecar, so each must arrive live, over the socket. The Console's own
    // pipeline batches captured lines on a 100 ms timer, which delivers each; the test waits on
    // the snapshot, not on time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ConsoleSidecarStreamingTests {
        @Test("A sidecar shows each line the host logs as it is logged, over a socket in a long container path, and its filter reaches the host")
        func linesStreamLive() async throws {
            let container = FileManager.default.temporaryDirectory
                .appending(path: "ConsoleSidecarStreamingTests-\(UUID().uuidString)")
                .appending(path: String(repeating: "Shared-AppGroup-", count: 6))
            let socketPath = container.appending(path: "drawer.sock").path
            let storeDirectory = container.appending(path: "DebugDrawer")
            let store = ConsoleLogStore(muteStorage: FakeConsoleMuteStorage())
            let console = ConsoleModel(store: store, sessions: ConsoleSessionsModel())
            let registry = DebugDrawerModelRegistry()
            registry.register(console, id: ConsolePlugin().id)
            let socketServer = DebugDrawerSocketServer(registry: registry, socketPath: socketPath)
            let storeServer = DebugDrawerAppGroupStoreServer(registry: registry, directory: storeDirectory)
            try storeServer.start()
            try socketServer.start()
            let sut = try DebugDrawerSidecarTransport(socketPath: socketPath, storeDirectory: storeDirectory)
            for await channel in sut.$channel.values where channel == .socket {
                break
            }
            let remote = try await sut.connect(toPlugin: ConsolePlugin().id, snapshot: ConsoleSnapshot.self, command: ConsoleCommand.self)
            let texts = ["Feed loaded", "Cart updated", "Order 1042 placed"]
            let before = remote.snapshot.log.lines
            var seen: [[String]] = []

            for (offset, text) in texts.enumerated() {
                store.ingest(LogLine(
                    timestamp: Date(timeIntervalSince1970: 1_800_000_000 + Double(offset)), text: text, source: .sink, level: .info,
                    subsystem: "com.example.shop", category: "checkout"
                ))
                for await snapshot in remote.snapshots() where snapshot.log.lines.count == offset + 1 {
                    seen.append(snapshot.log.lines.map(\.text))
                    break
                }
            }
            remote.send(ConsoleCommand(.filter(.setSearchText("order"))))
            for await snapshot in remote.snapshots() where snapshot.log.searchText == "order" {
                break
            }

            #expect(socketPath.utf8.count > 104)
            #expect(before.isEmpty)
            #expect(seen == [["Feed loaded"], ["Feed loaded", "Cart updated"], texts])
            #expect(sut.channel == .socket)
            #expect(console.snapshot.log.searchText == "order")
            socketServer.stop()
            storeServer.stop()
        }
    }
#endif
