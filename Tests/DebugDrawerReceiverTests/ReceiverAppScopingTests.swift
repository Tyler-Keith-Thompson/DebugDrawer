@testable import DebugDrawerReceiver
import Foundation
import Testing

/// A capability each test app serves: a log level a sidecar sets.
@MainActor
private final class LogLevelModel: DebugDrawerPluginModel {
    struct Snapshot: Codable, Equatable, Sendable {
        var level = "info"
    }

    enum Command: Codable, Equatable, Sendable {
        case set(String)
        case reset
    }

    @Published private(set) var snapshot = Snapshot()

    func perform(_ command: Command) {
        switch command {
        case let .set(level): snapshot.level = level
        case .reset: snapshot.level = "info"
        }
    }
}

// Two apps of one group in one process: two receivers handed the same group's store, each naming
// another app through its identity, as the main bundle would in each app. Each test leaves command
// files where a sidecar's transport would for one app (a `StoreDocument` per file in that app's
// `commands/`), then starts the receivers, which perform what waits before `start()` returns.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ReceiverAppScopingTests {
    @Test("Two apps' receivers on one group's store each perform only the commands left in their own directory, in their own sessions")
    func commandsAndSessionsScopedPerApp() throws {
        let store = FileManager.default.temporaryDirectory.appending(path: "ReceiverAppScopingTests-\(UUID().uuidString)")
        let shopLevel = LogLevelModel()
        let walletLevel = LogLevelModel()
        let shopSessions = DebugDrawerSessions(maximumDuration: 300)
        let walletSessions = DebugDrawerSessions(maximumDuration: 300)
        let shop = DebugDrawerReceiver(directory: store, sessions: shopSessions)
        shop.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
        shop.enable(.model(shopLevel, id: "LogLevel", scope: .persistent))
        let wallet = DebugDrawerReceiver(directory: store, sessions: walletSessions)
        wallet.identity = AppPresence.Identity(bundleIdentifier: "com.example.wallet", displayName: "Wallet", version: "1.0", build: "12")
        wallet.enable(.model(walletLevel, id: "LogLevel", scope: .persistent))
        let shopLayout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(of: "com.example.shop", inStore: store))
        #expect(shopLayout.create())
        let shopCommands: [(String, Data)] = try [
            (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            ("LogLevel", TransportMessage.payload(LogLevelModel.Command.set("debug")))
        ]
        for (index, (id, payload)) in shopCommands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try shopLayout.write(document.encoded(), to: shopLayout.commands.appending(path: "\(index).json"))
        }

        try shop.start()
        try wallet.start()
        defer {
            shop.stop()
            wallet.stop()
        }

        #expect(shop.appDirectory == store.appending(path: "apps/com.example.shop", directoryHint: .isDirectory))
        #expect(wallet.appDirectory == store.appending(path: "apps/com.example.wallet", directoryHint: .isDirectory))
        #expect(shopLevel.snapshot.level == "debug")
        #expect(walletLevel.snapshot.level == "info")
        #expect(shopSessions.snapshot.isActive)
        #expect(!walletSessions.snapshot.isActive)
        #expect(shopSessions.auditLog.map(\.capability) == [DebugDrawerSessions.pluginID, "LogLevel"])
        #expect(walletSessions.auditLog.isEmpty)
        #expect(shopLayout.messageFiles(in: shopLayout.commands).isEmpty)
    }

    @Test("A receiver never reads, removes or writes another app's directory: its commands wait and its capture data stays its own")
    func neverTouchesAnotherAppsDirectory() async throws {
        func files(in directory: URL) throws -> [String: Data] {
            var files: [String: Data] = [:]
            for path in try FileManager.default.subpathsOfDirectory(atPath: directory.path) {
                var isDirectory: ObjCBool = false
                let url = directory.appending(path: path)
                guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { continue }
                files[path] = try Data(contentsOf: url)
            }
            return files
        }
        let store = FileManager.default.temporaryDirectory.appending(path: "ReceiverAppScopingTests-\(UUID().uuidString)")
        let walletLayout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(of: "com.example.wallet", inStore: store))
        #expect(walletLayout.create())
        let walletCommand = try StoreDocument(TransportMessage(
            kind: .command, pluginID: DebugDrawerSessions.pluginID, payload: TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))
        )).encoded()
        let walletCapture = try StoreDocument(TransportMessage(
            kind: .snapshot, pluginID: "LogLevel", payload: TransportMessage.payload(LogLevelModel.Snapshot(level: "wallet's secret"))
        )).encoded()
        try walletLayout.write(walletCommand, to: walletLayout.commands.appending(path: "0.json"))
        try walletLayout.write(walletCapture, to: walletLayout.snapshotFile(for: "LogLevel"))
        let walletFilesBefore = try files(in: AppGroupStoreLayout.appDirectory(of: "com.example.wallet", inStore: store))
        let shopLevel = LogLevelModel()
        let shopSessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = DebugDrawerReceiver(directory: store, sessions: shopSessions)
        sut.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
        sut.enable(.model(shopLevel, id: "LogLevel", scope: .persistent))
        let shopLayout = AppGroupStoreLayout(directory: sut.appDirectory)
        #expect(shopLayout.create())
        let shopSnapshot = shopLayout.snapshotFile(for: "LogLevel")
        let watcher = try #require(DirectoryWatcher(directory: shopLayout.snapshots))
        // The shop's own session, so its capability is served: the wallet's command, had it reached
        // the shop, would be refused as one more session and audited.
        shopSessions.perform(.open(duration: 60))

        try sut.start()
        if !FileManager.default.fileExists(atPath: shopSnapshot.path) {
            for await _ in watcher.changes where FileManager.default.fileExists(atPath: shopSnapshot.path) {
                break
            }
        }
        watcher.cancel()
        let served = try #require(StoreDocument.decoded(from: Data(contentsOf: shopSnapshot)))
        let servedSnapshot = try JSONDecoder().decode(LogLevelModel.Snapshot.self, from: served.message.payload)
        sut.stop()
        let walletFilesAfter = try files(in: AppGroupStoreLayout.appDirectory(of: "com.example.wallet", inStore: store))
        let appsInStore = try FileManager.default.contentsOfDirectory(atPath: store.path).sorted()
        let appDirectories = try FileManager.default.contentsOfDirectory(atPath: AppGroupStoreLayout.appsDirectory(inStore: store).path).sorted()

        #expect(walletFilesAfter == walletFilesBefore)
        #expect(shopSessions.auditLog.count == 1)
        #expect(servedSnapshot == LogLevelModel.Snapshot(level: "info"))
        #expect(appsInStore == ["apps"])
        #expect(appDirectories == ["com.example.shop", "com.example.wallet"])
    }

    @Test("A command in an app's directory naming another app's capability is refused as unknown, inside a session too")
    func anotherAppsCapabilityIsUnknown() throws {
        let store = FileManager.default.temporaryDirectory.appending(path: "ReceiverAppScopingTests-\(UUID().uuidString)")
        let walletLevel = LogLevelModel()
        let wallet = DebugDrawerReceiver(directory: store, sessions: DebugDrawerSessions(maximumDuration: 300))
        wallet.identity = AppPresence.Identity(bundleIdentifier: "com.example.wallet", displayName: "Wallet", version: "1.0", build: "12")
        wallet.enable(.model(walletLevel, id: "Wallet.LogLevel", scope: .persistent))
        let shopSessions = DebugDrawerSessions(maximumDuration: 300)
        let shop = DebugDrawerReceiver(directory: store, sessions: shopSessions)
        shop.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
        shop.enable(.model(LogLevelModel(), id: "Shop.LogLevel", scope: .persistent))
        let shopLayout = AppGroupStoreLayout(directory: shop.appDirectory)
        #expect(shopLayout.create())
        let commands: [(String, Data)] = try [
            (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            ("Wallet.LogLevel", TransportMessage.payload(LogLevelModel.Command.set("debug")))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try shopLayout.write(document.encoded(), to: shopLayout.commands.appending(path: "\(index).json"))
        }

        try wallet.start()
        try shop.start()
        defer {
            shop.stop()
            wallet.stop()
        }
        let refusal = shopSessions.auditLog.last

        #expect(walletLevel.snapshot.level == "info")
        #expect(refusal?.capability == "Wallet.LogLevel")
        #expect(refusal?.event == .commandRefused(.unknownCapability))
        #expect(refusal?.sessionID != nil)
    }

    @Test("A store in the flat layout from before per-app directories is neither performed nor removed")
    func flatLayoutIgnored() throws {
        let store = FileManager.default.temporaryDirectory.appending(path: "ReceiverAppScopingTests-\(UUID().uuidString)")
        let flat = AppGroupStoreLayout(directory: store)
        #expect(flat.create())
        let command = try StoreDocument(TransportMessage(
            kind: .command, pluginID: DebugDrawerSessions.pluginID, payload: TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))
        )).encoded()
        try flat.write(command, to: flat.commands.appending(path: "0.json"))
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = DebugDrawerReceiver(directory: store, sessions: sessions)
        sut.enable(.model(LogLevelModel(), id: "LogLevel", scope: .persistent))

        try sut.start()
        sut.stop()

        #expect(sessions.auditLog.isEmpty)
        #expect(!sessions.snapshot.isActive)
        #expect(flat.messageFiles(in: flat.commands).map(\.lastPathComponent) == ["0.json"])
    }

    @Test("The app registers itself in its own directory: bundle ID, name, version, build, capabilities and protocol version")
    func presenceInAppDirectory() throws {
        let store = FileManager.default.temporaryDirectory.appending(path: "ReceiverAppScopingTests-\(UUID().uuidString)")
        let sut = DebugDrawerReceiver(directory: store, sessions: DebugDrawerSessions(maximumDuration: 300))
        sut.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
        sut.enable(.model(LogLevelModel(), id: "Shop.LogLevel", scope: .persistent))
        let file = store.appending(path: "apps/com.example.shop/presence.json")
        let expectedIdentity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")

        try sut.start()
        let written = try #require(AppPresence.decoded(from: Data(contentsOf: file)))
        sut.stop()

        #expect(written.schemaVersion == 2)
        #expect(written.identity == expectedIdentity)
        #expect(written.capabilities == [DebugDrawerSessions.pluginID, "Shop.LogLevel"])
        #expect(written.hello == TransportHello.current)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }
}
