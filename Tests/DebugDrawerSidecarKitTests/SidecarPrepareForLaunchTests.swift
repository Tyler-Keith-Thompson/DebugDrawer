#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import DebugDrawerTestSupport
    import Foundation
    import SwiftUI
    import Testing

    /// The app's flag service, read back by the tests.
    @MainActor
    private final class FakeFlagService: DebugDrawerFeatureFlagAdapter {
        private(set) var overrides: [String: DebugDrawerFeatureFlagValue] = [:]

        func overridableFlags() -> [DebugDrawerFeatureFlag] {
            [DebugDrawerFeatureFlag(key: "new-checkout", value: overrides["new-checkout"] ?? .bool(false))]
        }

        func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
            overrides[key] = value
        }

        func clearOverride(forKey key: String) {
            overrides[key] = nil
        }
    }

    /// A capability that adds what each command says, so the commands performed show in its total.
    @MainActor
    private final class TallyModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var total = 0
        }

        enum Command: Codable, Sendable {
            case add(Int)
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            switch command {
            case let .add(amount): snapshot.total += amount
            }
        }
    }

    /// Holds the transport a hosted plugin was made over, so a test sends through it.
    @MainActor
    private final class TransportBox<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable> {
        var transport: DebugDrawerPluginTransport<Snapshot, Command>?
    }

    /// A plugin that draws nothing: the test drives its transport.
    private struct TransportPlugin: DebugDrawerPlugin {
        var title = "Transport"
        var icon = "circle"

        var body: some View {
            EmptyView()
        }
    }

    // The tester's flow (DD-296): the sidecar first, then the app. A receiver stands in for each
    // launch of a production app; the sidecar's connection is made while no receiver runs, leaves
    // a session's open and a command in the store, and the next receiver to start performs them
    // as it starts, before `start()` returns. Each wait after that is for the snapshot, the
    // published state or the store change the step produces, never for time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarPrepareForLaunchTests {
        private let shop = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")

        @Test("A stopped app is listed as not running; a session's open and a flag override sent then apply in that session as it launches")
        func stoppedAppAppliesWhatWasPrepared() async throws {
            let suite = temporarySuiteName("SidecarPrepareForLaunchTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let root = FileManager.default.temporaryDirectory.appending(path: "SidecarPrepareForLaunchTests-\(UUID().uuidString)")
            let store = root.appending(path: "DebugDrawer")
            let caches = root.appending(path: "Sidecar Caches")
            let flagsBox = TransportBox<DebugDrawerFeatureFlagOverrides.Snapshot, DebugDrawerFeatureFlagOverrides.Command>()
            let flags = DebugDrawerSidecarPlugin(
                id: DebugDrawerFeatureFlagOverrides.pluginID, title: "Flags", icon: "flag",
                snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self, command: DebugDrawerFeatureFlagOverrides.Command.self
            ) { transport in
                flagsBox.transport = transport
                return TransportPlugin()
            }
            // The launch before: the sidecar reads the flags within a session, then the app stops.
            let earlierSessions = DebugDrawerSessions(maximumDuration: 300)
            let earlier = DebugDrawerReceiver(directory: store, sessions: earlierSessions)
            earlier.identity = shop
            earlier.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: FakeFlagService(), defaults: defaults)))
            try earlier.start()
            earlierSessions.perform(.open(duration: 60))
            let running = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let reading = try DebugDrawerSidecarConnection(app: running, snapshotCacheDirectory: caches)
            _ = try await reading.host(flags)
            reading.close()
            earlierSessions.perform(.end)
            earlier.stop()
            let stopped = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let sut = try DebugDrawerSidecarConnection(app: stopped, snapshotCacheDirectory: caches)
            defer { sut.close() }
            let service = FakeFlagService()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = shop
            receiver.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: service, defaults: defaults)))
            let expectedPrepared = DebugDrawerFeatureFlagOverrides.Snapshot(
                flags: [DebugDrawerFeatureFlag(key: "new-checkout", value: .bool(false))], overriddenKeys: []
            )

            sut.openSession(duration: 120)
            let waitingBeforeLaunch = sut.isWaitingForLaunch
            _ = try sut.prepare(flags)
            let prepared = try #require(flagsBox.transport)
            let shownBeforeLaunch = prepared.snapshot
            let preparedBeforeLaunch = sut.preparedForLaunch
            prepared.send(.setOverride(key: "new-checkout", value: .bool(true)))
            try receiver.start()
            defer { receiver.stop() }
            for await snapshot in prepared.snapshots() where snapshot.overriddenKeys == ["new-checkout"] {
                break
            }
            for await isWaiting in sut.$isWaitingForLaunch.values where !isWaiting {
                break
            }
            for await ids in sut.$preparedForLaunch.values where ids.isEmpty {
                break
            }

            let session = try #require(sessions.snapshot.session)
            let expectedEvents: [DebugDrawerAuditEntry.Event] = [.sessionOpened(expires: session.expires), .commandApplied]
            #expect(running.isRunning)
            #expect(!stopped.isRunning)
            #expect(stopped.capabilities == [DebugDrawerFeatureFlagOverrides.pluginID, DebugDrawerSessions.pluginID].sorted())
            #expect(waitingBeforeLaunch)
            #expect(shownBeforeLaunch == expectedPrepared)
            #expect(preparedBeforeLaunch == [DebugDrawerFeatureFlagOverrides.pluginID])
            #expect(service.overrides == ["new-checkout": .bool(true)])
            #expect(session.expires.timeIntervalSince(session.opened) == 120)
            #expect(sessions.auditLog.map(\.event) == expectedEvents)
            #expect(sessions.auditLog.map(\.capability) == [DebugDrawerSessions.pluginID, DebugDrawerFeatureFlagOverrides.pluginID])
            #expect(sessions.auditLog.allSatisfy { $0.sessionID == session.id })
        }

        @Test("An app that never launched, addressed by bundle ID, applies at its first launch a session's open and a command prepared before")
        func neverLaunchedAppAppliesWhatWasPrepared() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "SidecarPrepareForLaunchTests-\(UUID().uuidString)")
            let store = root.appending(path: "DebugDrawer")
            let caches = root.appending(path: "Sidecar Caches")
            let appDirectory = AppGroupStoreLayout.appDirectory(of: "com.example.shop", inStore: store)
            let app = DebugDrawerSidecarApp(
                bundleIdentifier: "com.example.shop", displayName: "Shop", version: "", build: "",
                capabilities: [DebugDrawerSessions.pluginID, "Shop.Tally"], protocolVersion: 2, lastSeen: .distantPast,
                storeDirectory: appDirectory, isRunning: false
            )
            // What a sidecar kept as an earlier install of the app served the tally.
            SidecarSnapshotCache(appDirectory: appDirectory, bundleIdentifier: "com.example.shop", in: caches)
                .store(TallyModel.Snapshot(total: 0), of: "Shop.Tally")
            let box = TransportBox<TallyModel.Snapshot, TallyModel.Command>()
            let tally = DebugDrawerSidecarPlugin(
                id: "Shop.Tally", title: "Tally", icon: "number", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self
            ) { transport in
                box.transport = transport
                return TransportPlugin()
            }
            let listedBeforeLaunch = DebugDrawerSidecarAppList(storeDirectory: store).apps
            let sut = try DebugDrawerSidecarConnection(app: app, snapshotCacheDirectory: caches)
            defer { sut.close() }
            let model = TallyModel()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = shop
            receiver.enable(.model(model, id: "Shop.Tally", scope: .persistent))

            sut.openSession(duration: 60)
            _ = try sut.prepare(tally)
            try #require(box.transport).send(.add(5))
            try receiver.start()
            defer { receiver.stop() }
            for await isWaiting in sut.$isWaitingForLaunch.values where !isWaiting {
                break
            }

            #expect(listedBeforeLaunch.isEmpty)
            #expect(sessions.snapshot.isActive)
            #expect(model.snapshot.total == 5)
            #expect(sessions.auditLog.last?.event == .commandApplied)
        }

        @Test("A capability the sidecar never read can't be prepared, and says so at once, as does one that only shows what the app collects")
        func neverReadCantBePrepared() throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "SidecarPrepareForLaunchTests-\(UUID().uuidString)")
            let appDirectory = AppGroupStoreLayout.appDirectory(of: "com.example.shop", inStore: root.appending(path: "DebugDrawer"))
            let caches = root.appending(path: "Sidecar Caches")
            let app = DebugDrawerSidecarApp(
                bundleIdentifier: "com.example.shop", displayName: "Shop", version: "", build: "",
                capabilities: [DebugDrawerSessions.pluginID, "Shop.Tally", "Shop.Log"], protocolVersion: 2, lastSeen: .distantPast,
                storeDirectory: appDirectory, isRunning: false
            )
            SidecarSnapshotCache(appDirectory: appDirectory, bundleIdentifier: "com.example.shop", in: caches)
                .store(TallyModel.Snapshot(total: 3), of: "Shop.Log")
            let tally = DebugDrawerSidecarPlugin(
                id: "Shop.Tally", title: "Tally", icon: "number", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self
            ) { _ in TransportPlugin() }
            var collected = DebugDrawerSidecarPlugin(
                id: "Shop.Log", title: "Log", icon: "text.alignleft", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self
            ) { _ in TransportPlugin() }
            collected.preparesForLaunch = false
            let sut = try DebugDrawerSidecarConnection(app: app, snapshotCacheDirectory: caches)
            defer { sut.close() }

            #expect(throws: DebugDrawerSidecarConnection.NeverRead()) { try sut.prepare(tally) }
            #expect(throws: DebugDrawerSidecarConnection.NeverRead()) { try sut.prepare(collected) }
            #expect(sut.hosted.isEmpty)
            #expect(sut.preparedForLaunch.isEmpty)
            #expect(DebugDrawerSidecarPlugin.featureFlagOverrides.preparesForLaunch)
            #expect(!DebugDrawerSidecarPlugin.diagnosticsCapture.preparesForLaunch)
            #expect(!DebugDrawerSidecarPlugin.appState.preparesForLaunch)
        }

        @Test("openSession on an app not running leaves the open in its store, waiting for launch until the app takes it, then reads open")
        func openWaitsForLaunch() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "SidecarPrepareForLaunchTests-\(UUID().uuidString)")
            let store = root.appending(path: "DebugDrawer")
            let appDirectory = AppGroupStoreLayout.appDirectory(of: "com.example.shop", inStore: store)
            let app = DebugDrawerSidecarApp(
                bundleIdentifier: "com.example.shop", displayName: "Shop", version: "", build: "",
                capabilities: [DebugDrawerSessions.pluginID, "Shop.Tally"], protocolVersion: 2, lastSeen: .distantPast,
                storeDirectory: appDirectory, isRunning: false
            )
            let sut = try DebugDrawerSidecarConnection(app: app, snapshotCacheDirectory: root.appending(path: "Sidecar Caches"))
            defer { sut.close() }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = shop
            receiver.enable(.model(TallyModel(), id: "Shop.Tally", scope: .persistent))
            let layout = AppGroupStoreLayout(directory: appDirectory)
            let before = sut.isWaitingForLaunch

            sut.openSession(duration: 60)
            let waiting = sut.isWaitingForLaunch
            let left = try layout.messageFiles(in: layout.commands).map { file in
                try #require(StoreDocument.decoded(from: Data(contentsOf: file))).message.pluginID
            }
            try receiver.start()
            defer { receiver.stop() }
            for await isWaiting in sut.$isWaitingForLaunch.values where !isWaiting {
                break
            }
            var read: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>?
            for await transport in sut.$sessions.values where transport != nil {
                read = transport
                break
            }
            let transport = try #require(read)
            for await state in transport.snapshots() where state.isActive {
                break
            }

            #expect(!before)
            #expect(waiting)
            #expect(left == [DebugDrawerSessions.pluginID])
            #expect(transport.snapshot.session?.id == sessions.snapshot.session?.id)
        }

        @Test("A queued open survives the store's command cap: of 300 commands after it, the 255 newest are kept and applied in its session")
        func queuedOpenSurvivesTheCap() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "SidecarPrepareForLaunchTests-\(UUID().uuidString)")
            let store = root.appending(path: "DebugDrawer")
            let caches = root.appending(path: "Sidecar Caches")
            let appDirectory = AppGroupStoreLayout.appDirectory(of: "com.example.shop", inStore: store)
            let app = DebugDrawerSidecarApp(
                bundleIdentifier: "com.example.shop", displayName: "Shop", version: "", build: "",
                capabilities: [DebugDrawerSessions.pluginID, "Shop.Tally"], protocolVersion: 2, lastSeen: .distantPast,
                storeDirectory: appDirectory, isRunning: false
            )
            SidecarSnapshotCache(appDirectory: appDirectory, bundleIdentifier: "com.example.shop", in: caches)
                .store(TallyModel.Snapshot(), of: "Shop.Tally")
            let box = TransportBox<TallyModel.Snapshot, TallyModel.Command>()
            let tally = DebugDrawerSidecarPlugin(
                id: "Shop.Tally", title: "Tally", icon: "number", snapshot: TallyModel.Snapshot.self, command: TallyModel.Command.self
            ) { transport in
                box.transport = transport
                return TransportPlugin()
            }
            let sut = try DebugDrawerSidecarConnection(app: app, snapshotCacheDirectory: caches)
            defer { sut.close() }
            let model = TallyModel()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = shop
            receiver.enable(.model(model, id: "Shop.Tally", scope: .persistent))
            let layout = AppGroupStoreLayout(directory: appDirectory)
            let sent = 1...300
            let kept = (300 - AppGroupStoreLayout.maximumCommandFiles + 2)...300
            let expectedTotal = kept.reduce(0, +)

            sut.openSession(duration: 60)
            _ = try sut.prepare(tally)
            let prepared = try #require(box.transport)
            for amount in sent {
                prepared.send(.add(amount))
            }
            let waiting = try layout.messageFiles(in: layout.commands).map { file in
                try #require(StoreDocument.decoded(from: Data(contentsOf: file))).message.pluginID
            }
            try receiver.start()
            defer { receiver.stop() }

            let session = try #require(sessions.snapshot.session)
            let applied = sessions.auditLog.filter { $0.event == .commandApplied }
            #expect(waiting.count == AppGroupStoreLayout.maximumCommandFiles)
            #expect(waiting.first == DebugDrawerSessions.pluginID)
            #expect(waiting.dropFirst().allSatisfy { $0 == "Shop.Tally" })
            #expect(model.snapshot.total == expectedTotal)
            #expect(applied.count == kept.count)
            #expect(applied.allSatisfy { $0.sessionID == session.id })
        }

        @Test("What the sidecar reads is kept in its own cache directory, never in the app group's store")
        func cacheLivesOutsideTheStore() async throws {
            let suite = temporarySuiteName("SidecarPrepareForLaunchTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let root = FileManager.default.temporaryDirectory.appending(path: "SidecarPrepareForLaunchTests-\(UUID().uuidString)")
            let store = root.appending(path: "DebugDrawer")
            let caches = root.appending(path: "Sidecar Caches")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = shop
            receiver.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: FakeFlagService(), defaults: defaults)))
            try receiver.start()
            sessions.perform(.open(duration: 60))
            let app = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let sut = try DebugDrawerSidecarConnection(app: app, snapshotCacheDirectory: caches)

            _ = try await sut.host(.featureFlagOverrides)
            sut.close()
            sessions.perform(.end)
            receiver.stop()

            let inCaches = try #require(FileManager.default.enumerator(atPath: caches.path)?.allObjects as? [String])
            let inStore = try #require(FileManager.default.enumerator(atPath: store.path)?.allObjects as? [String])
            let flagsFile = "\(AppGroupStoreLayout.fileName(DebugDrawerFeatureFlagOverrides.pluginID)).json"
            #expect(inCaches.contains { $0.hasSuffix("-com.example.shop/\(flagsFile)") })
            #expect(!inStore.contains { $0.hasSuffix(flagsFile) })
            #expect(!caches.path.hasPrefix(store.path))
            #expect(SidecarSnapshotCache.defaultDirectory.lastPathComponent == "DebugDrawer Sidecar Snapshots")
        }
    }
#endif
