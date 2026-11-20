#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing

    /// A model a receiver serves, so the receiver has a capability to list.
    @MainActor
    private final class LevelModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var level = "info"
        }

        enum Command: Codable, Sendable {
            case reset
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            snapshot = Snapshot()
        }
    }

    /// The host's remote switch for its receiver, as its configuration would hold it.
    @MainActor
    private final class HostGate {
        var isOn = true
    }

    // Two "apps" in one process: two receivers on one temporary group store, each naming another
    // app, as two production apps in a group would. The kit's list hears each presence file as it
    // lands and goes through its directory's dispatch source; every wait is for the list to change,
    // never for time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarAppListTests {
        @Test("Two apps running a receiver in the group are both listed; one that stops drops off")
        func listsReceiversAsTheyStartAndStop() async throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarAppListTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let shop = DebugDrawerReceiver(directory: store, sessions: DebugDrawerSessions(maximumDuration: 60))
            shop.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            shop.enable(.model(LevelModel(), id: "Shop.LogLevel", scope: .session(revertWith: .reset)))
            let wallet = DebugDrawerReceiver(directory: store, sessions: DebugDrawerSessions(maximumDuration: 60))
            wallet.identity = AppPresence.Identity(bundleIdentifier: "com.example.wallet", displayName: "Wallet", version: "1.0", build: "12")
            wallet.enable(.model(LevelModel(), id: "Wallet.LogLevel", scope: .persistent))
            let sut = DebugDrawerSidecarAppList(storeDirectory: store)
            let before = sut.apps

            try shop.start()
            try wallet.start()
            for await apps in sut.$apps.values where apps.count == 2 {
                break
            }
            let listed = sut.apps
            wallet.stop()
            for await apps in sut.$apps.values where apps.count == 1 {
                break
            }
            let afterStop = sut.apps
            shop.stop()

            #expect(before.isEmpty)
            #expect(sut.error == nil)
            #expect(listed.map(\.bundleIdentifier) == ["com.example.shop", "com.example.wallet"])
            #expect(listed.map(\.displayName) == ["Shop", "Wallet"])
            #expect(listed.map(\.version) == ["2.4", "1.0"])
            #expect(listed.map(\.build) == ["881", "12"])
            #expect(listed.first?.capabilities == ["DebugDrawer.Sessions", "Shop.LogLevel"])
            #expect(listed.last?.capabilities == ["DebugDrawer.Sessions", "Wallet.LogLevel"])
            #expect(listed.allSatisfy { $0.requiresSession && $0.isServing && $0.storeDirectory == store })
            #expect(afterStop.map(\.bundleIdentifier) == ["com.example.shop"])
        }

        @Test("An app already serving when the sidecar starts is listed at once, and a capability it enables later shows up")
        func listsAnAppAlreadyServingAndFollowsItsCapabilities() async throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarAppListTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let receiver = DebugDrawerReceiver(directory: store, sessions: DebugDrawerSessions(maximumDuration: 60))
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.model(LevelModel(), id: "Shop.LogLevel", scope: .persistent))
            try receiver.start()

            let sut = DebugDrawerSidecarAppList(storeDirectory: store)
            let atStart = sut.apps.map(\.capabilities)
            receiver.enable(.model(LevelModel(), id: "Shop.Theme", scope: .persistent))
            for await apps in sut.$apps.values where apps.first?.capabilities.count == 3 {
                break
            }
            receiver.stop()

            #expect(atStart == [["DebugDrawer.Sessions", "Shop.LogLevel"]])
            #expect(sut.apps.map(\.capabilities) == [["DebugDrawer.Sessions", "Shop.LogLevel", "Shop.Theme"]])
        }

        @Test("An app whose host turns the receiver off stays listed, serving nothing, until the host turns it back on")
        func receiverTurnedOffServesNothing() async throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarAppListTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let gate = HostGate()
            let receiver = DebugDrawerReceiver(directory: store, sessions: DebugDrawerSessions(maximumDuration: 60)) { gate.isOn }
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.model(LevelModel(), id: "Shop.LogLevel", scope: .persistent))
            try receiver.start()
            let sut = DebugDrawerSidecarAppList(storeDirectory: store)

            gate.isOn = false
            receiver.reevaluateGates()
            for await apps in sut.$apps.values where apps.first?.isServing == false {
                break
            }
            let turnedOff = sut.apps
            gate.isOn = true
            receiver.reevaluateGates()
            for await apps in sut.$apps.values where apps.first?.isServing == true {
                break
            }
            receiver.stop()

            #expect(turnedOff.map(\.bundleIdentifier) == ["com.example.shop"])
            #expect(turnedOff.first?.capabilities == [])
            #expect(sut.apps.first?.capabilities == ["DebugDrawer.Sessions", "Shop.LogLevel"])
        }

        @Test("A debug build's store server lists its app with the models it serves, and drops off as it stops")
        func storeServerIsListed() async throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarAppListTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let registry = DebugDrawerModelRegistry()
            registry.register(LevelModel(), id: "Shop.LogLevel")
            let server = DebugDrawerAppGroupStoreServer(registry: registry, directory: store)
            server.identity = AppPresence.Identity(
                bundleIdentifier: "com.example.shop.debug", displayName: "Shop Debug", version: "2.5", build: "900"
            )
            let sut = DebugDrawerSidecarAppList(storeDirectory: store)

            try server.start()
            for await apps in sut.$apps.values where !apps.isEmpty {
                break
            }
            let listed = sut.apps
            server.stop()
            for await apps in sut.$apps.values where apps.isEmpty {
                break
            }

            #expect(listed.map(\.displayName) == ["Shop Debug"])
            #expect(listed.first?.capabilities == ["Shop.LogLevel"])
            #expect(listed.first?.requiresSession == false)
            #expect(sut.apps.isEmpty)
        }

        @Test("A group with no container lists nothing and says why")
        func noContainer() {
            let sut = DebugDrawerSidecarAppList(groupIdentifier: "group.com.example.missing") { _ in nil }

            #expect(sut.apps.isEmpty)
            #expect(sut.error == .noAppGroupContainer)
            #expect(sut.storeDirectory == nil)
        }

        @Test("A file in the presence directory that isn't a presence, and a write in progress, are left out")
        func unreadableFilesAreSkipped() throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarAppListTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let presence = AppPresence.directory(inStore: store)
            try FileManager.default.createDirectory(at: presence, withIntermediateDirectories: true)
            try Data("not json".utf8).write(to: presence.appending(path: "broken.json"))
            let valid = AppPresence(
                identity: AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "", build: ""),
                capabilities: ["Shop.LogLevel"], lastSeen: Date(timeIntervalSince1970: 1_800_000_000)
            )
            try valid.encoded().write(to: presence.appending(path: "com.example.shop.json"))
            try valid.encoded().write(to: presence.appending(path: "com.example.other.json.1234.partial"))

            let sut = DebugDrawerSidecarAppList(storeDirectory: store)

            #expect(sut.apps.map(\.bundleIdentifier) == ["com.example.shop"])
            #expect(sut.apps.first?.lastSeen == Date(timeIntervalSince1970: 1_800_000_000))
            #expect(sut.apps.first?.versionLine == "No version")
        }
    }
#endif
