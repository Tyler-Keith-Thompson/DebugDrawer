#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing

    /// A model whose snapshot is a tally, changed by commands.
    @MainActor
    private final class TallyModel: DebugDrawerPluginModel {
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

    // Two debug builds of a group's apps in one process: two store servers handed the same group's
    // store, each naming another app through its identity, as the main bundle would in each app,
    // with a model under the same ID. A sidecar's store transport reaches one app through that
    // app's directory; every wait is for a snapshot, never for time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct StoreServerAppScopingTests {
        @Test("Two apps' store servers on one group's store each serve their own directory: a sidecar's command reaches only the app it names")
        func commandsAndSnapshotsScopedPerApp() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "StoreServerAppScopingTests-\(UUID().uuidString)")
            let group = try DebugDrawerAppGroupContainer(groupIdentifier: "TEAMID.com.example.debug") { _ in container }
            let store = group.storeDirectory
            let shopModel = TallyModel()
            let shopRegistry = DebugDrawerModelRegistry()
            shopRegistry.register(shopModel, id: "Tally")
            let shop = DebugDrawerAppGroupStoreServer(registry: shopRegistry, directory: store)
            shop.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop.debug", displayName: "Shop", version: "2.5", build: "900")
            let walletModel = TallyModel()
            let walletRegistry = DebugDrawerModelRegistry()
            walletRegistry.register(walletModel, id: "Tally")
            let wallet = DebugDrawerAppGroupStoreServer(registry: walletRegistry, directory: store)
            wallet.identity = AppPresence.Identity(bundleIdentifier: "com.example.wallet.debug", displayName: "Wallet", version: "1.1", build: "40")
            try shop.start()
            try wallet.start()
            defer {
                shop.stop()
                wallet.stop()
            }
            let shopViewer = try await DebugDrawerAppGroupStoreTransport(directory: group.appDirectory(of: "com.example.shop.debug"))
                .connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)
            let walletViewer = try await DebugDrawerAppGroupStoreTransport(directory: wallet.appDirectory)
                .connect(toPlugin: "Tally", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self)

            shopViewer.send(.add(3))
            for await snapshot in shopViewer.snapshots() where snapshot.count == 3 {
                break
            }
            walletViewer.send(.add(5))
            for await snapshot in walletViewer.snapshots() where snapshot.count == 5 {
                break
            }

            #expect(shopModel.snapshot.count == 3)
            #expect(walletModel.snapshot.count == 5)
            #expect(shop.appDirectory == group.appDirectory(of: "com.example.shop.debug"))
            #expect(try FileManager.default.contentsOfDirectory(atPath: store.path) == ["apps"])
            #expect(try FileManager.default.contentsOfDirectory(atPath: store.appending(path: "apps").path).sorted() == [
                "com.example.shop.debug", "com.example.wallet.debug"
            ])
        }
    }
#endif
