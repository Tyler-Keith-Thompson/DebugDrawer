#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerRemote
    @testable import DebugDrawerSidecarKit
    import DebugDrawerTestSupport
    import Foundation
    import Network
    import SwiftUI
    import Testing
    import ViewInspector

    /// The production app's flag service, read back by the tests.
    @MainActor
    private final class FakeFlagService: DebugDrawerFeatureFlagAdapter {
        private(set) var overrides: [String: DebugDrawerFeatureFlagValue] = [:]

        func overridableFlags() -> [DebugDrawerFeatureFlag] {
            [
                DebugDrawerFeatureFlag(key: "new-checkout", value: overrides["new-checkout"] ?? .bool(false)),
                DebugDrawerFeatureFlag(key: "button-color", value: overrides["button-color"] ?? .string("blue"))
            ]
        }

        func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
            overrides[key] = value
        }

        func clearOverride(forKey key: String) {
            overrides[key] = nil
        }
    }

    /// A model of the host's own, served beside the flags, so a grant can leave one out.
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

    /// A verifier that reads every token as the grant it was made with.
    private struct FixedGrantVerifier: DebugDrawerGrantVerifier {
        let grant: DebugDrawerGrant

        func verify(_ token: String) throws(DebugDrawerGrantVerificationError) -> DebugDrawerGrant {
            grant
        }
    }

    /// A value of every kind a snapshot holds, for the relay's JSON to carry.
    private struct EveryKind: Codable, Equatable {
        var count: Int
        var largest: UInt64
        var smallest: Int64
        var ratio: Double
        var isOn: Bool
        var name: String
        var date: Date
        var bytes: Data
        var missing: String?
        var nested: [String: [Int]]
        var values: [DebugDrawerUserDefaultsValue]
    }

    // The README's device-lab sidecar and Mac viewer ("A device lab: sidecars sharing their sessions
    // with a Mac"), verbatim: they compile against the kit.
    private struct CompanyLabSidecar: View {
        var body: some View {
            DebugDrawerSidecarView(groupIdentifier: "TEAMID.com.example.debug", plugins: [.featureFlagOverrides, .tweaks])
                .debugDrawerSidecarRelay()
        }
    }

    @MainActor
    private func showFlags(of viewer: DebugDrawerNetworkTransport) async throws -> AnyDebugDrawerPlugin? {
        let relay = try await viewer.connect(
            toPlugin: DebugDrawerSidecarRelay.pluginID, snapshot: DebugDrawerSidecarRelay.Snapshot.self, command: Never.self
        )
        guard relay.snapshot.pluginIDs.contains(DebugDrawerFeatureFlagOverrides.pluginID) else { return nil }
        return try await DebugDrawerSidecarPlugin.featureFlagOverrides.plugin(over: viewer)
    }

    // The device-lab bridge (DD-107): a Mac viewer pairs with the relay a sidecar serves on
    // loopback, and reads and drives a real production receiver, over a temporary app-group
    // directory, within the session the sidecar opened. Each wait is for the snapshot that step
    // should produce, never for time; the network is 127.0.0.1 alone, advertising nothing.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarRelayTests {
        private let flagsID = DebugDrawerFeatureFlagOverrides.pluginID

        @Test("A Mac paired by the sidecar's code sees the production app's flags in the sidecar's session, and its override reaches the host")
        func macViewerSeesAndControls() async throws {
            let suite = temporarySuiteName("SidecarRelayTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarRelayTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let service = FakeFlagService()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let model = DebugDrawerFeatureFlagOverrides(adapter: service, defaults: defaults)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.featureFlagOverrides(model))
            try receiver.start()
            defer { receiver.stop() }
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let connection = try DebugDrawerSidecarConnection(app: listed)
            defer { connection.close() }
            let relay = DebugDrawerSidecarRelay(connection: connection, configuration: .loopback)
            try await relay.start()
            defer { relay.stop() }
            for await sessionsRead in connection.$sessions.values where sessionsRead != nil {
                break
            }
            connection.openSession(duration: 60)
            let port = try #require(relay.server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let viewer = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Lab Mac")
            defer { viewer.close() }
            var shown: DebugDrawerPairingRequest?
            for await requests in relay.server.$pairingRequests.values where !requests.isEmpty {
                shown = requests.first
                break
            }
            try await viewer.pair(code: try #require(shown).code)
            let status = try await viewer.connect(
                toPlugin: DebugDrawerSidecarRelay.pluginID, snapshot: DebugDrawerSidecarRelay.Snapshot.self, command: Never.self
            )
            for await snapshot in status.snapshots() where snapshot.pluginIDs.contains(flagsID) {
                break
            }
            let flags = try await viewer.connect(
                toPlugin: flagsID, snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self, command: DebugDrawerFeatureFlagOverrides.Command.self
            )
            let hosted = try await DebugDrawerSidecarPlugin.featureFlagOverrides.plugin(over: viewer)
            let expectedKeys = ["new-checkout", "button-color"]
            let shownKeys = flags.snapshot.flags.map(\.key)

            try hosted.body.inspect().find(viewWithAccessibilityIdentifier: "Flag-new-checkout").find(ViewType.Toggle.self).tap()

            for await snapshot in model.$snapshot.values where snapshot.overriddenKeys == ["new-checkout"] {
                break
            }
            for await snapshot in flags.snapshots() where snapshot.overriddenKeys == ["new-checkout"] {
                break
            }
            #expect(shownKeys == expectedKeys)
            #expect(service.overrides == ["new-checkout": .bool(true)])
            #expect(sessions.auditLog.last?.capability == flagsID)
            #expect(sessions.auditLog.last?.event == .commandApplied)
            #expect(status.snapshot.bundleIdentifier == "com.example.shop")
            #expect(status.snapshot.pluginIDs == [flagsID])
            #expect(status.snapshot.sessionExpires == sessions.snapshot.session?.expires)
        }

        @Test("As the session ends the viewer sees the relay stop, a command it sends then reaches nothing, and the next session is relayed afresh")
        func sessionEndStopsTheRelay() async throws {
            let suite = temporarySuiteName("SidecarRelayTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarRelayTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let service = FakeFlagService()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let model = DebugDrawerFeatureFlagOverrides(adapter: service, defaults: defaults)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.featureFlagOverrides(model))
            try receiver.start()
            defer { receiver.stop() }
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let connection = try DebugDrawerSidecarConnection(app: listed)
            defer { connection.close() }
            let relay = DebugDrawerSidecarRelay(connection: connection, configuration: .loopback)
            try await relay.start()
            defer { relay.stop() }
            for await sessionsRead in connection.$sessions.values where sessionsRead != nil {
                break
            }
            connection.openSession(duration: 60)
            let port = try #require(relay.server.port.flatMap(NWEndpoint.Port.init(rawValue:)))
            let viewer = DebugDrawerNetworkTransport(endpoint: .hostPort(host: "127.0.0.1", port: port), viewerName: "Lab Mac")
            defer { viewer.close() }
            var shown: DebugDrawerPairingRequest?
            for await requests in relay.server.$pairingRequests.values where !requests.isEmpty {
                shown = requests.first
                break
            }
            try await viewer.pair(code: try #require(shown).code)
            let status = try await viewer.connect(
                toPlugin: DebugDrawerSidecarRelay.pluginID, snapshot: DebugDrawerSidecarRelay.Snapshot.self, command: Never.self
            )
            for await snapshot in status.snapshots() where snapshot.pluginIDs.contains(flagsID) {
                break
            }
            let flags = try await viewer.connect(
                toPlugin: flagsID, snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self, command: DebugDrawerFeatureFlagOverrides.Command.self
            )

            connection.endSession()
            for await snapshot in status.snapshots() where !snapshot.isRelaying {
                break
            }
            let ended = status.snapshot
            flags.send(.setOverride(key: "button-color", value: .string("red")))
            connection.openSession(duration: 60)
            for await snapshot in status.snapshots() where snapshot.pluginIDs.contains(flagsID) {
                break
            }
            flags.send(.setOverride(key: "new-checkout", value: .bool(true)))

            for await snapshot in model.$snapshot.values where snapshot.overriddenKeys == ["new-checkout"] {
                break
            }
            let refusals = sessions.auditLog.filter { entry in
                guard entry.capability == flagsID, case .commandRefused = entry.event else { return false }
                return true
            }
            #expect(ended.pluginIDs.isEmpty)
            #expect(ended.sessionExpires == nil)
            #expect(service.overrides == ["new-checkout": .bool(true)])
            #expect(refusals.isEmpty)
        }

        @Test("Under a grant policy the relay serves only the capabilities the session's grant lists")
        func relaysOnlyWhatTheGrantLists() async throws {
            let suite = temporarySuiteName("SidecarRelayTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarRelayTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let now = Date()
            let grant = DebugDrawerGrant(
                id: "g-\(UUID().uuidString)", subject: "tester@example.com", audiences: ["com.example.shop"], capabilities: [flagsID],
                notBefore: now.addingTimeInterval(-60), expires: now.addingTimeInterval(300)
            )
            let policy = DebugDrawerGrantPolicy(verifier: FixedGrantVerifier(grant: grant), audience: "com.example.shop")
            let sessions = DebugDrawerSessions(maximumDuration: 300, grantPolicy: policy)
            let model = DebugDrawerFeatureFlagOverrides(adapter: FakeFlagService(), defaults: defaults)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.featureFlagOverrides(model))
            receiver.enable(.model(LevelModel(), id: "Shop.LogLevel", scope: .persistent))
            try receiver.start()
            defer { receiver.stop() }
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let connection = try DebugDrawerSidecarConnection(app: listed)
            defer { connection.close() }
            let listener = FakeConnectionListener()
            let sut = DebugDrawerSidecarRelay(connection: connection, timer: ManualSessionTimer()) { registry in
                DebugDrawerNetworkServer(registry: registry, configuration: .loopback, listener: listener)
            }
            try await sut.start()
            for await sessionsRead in connection.$sessions.values where sessionsRead != nil {
                break
            }

            connection.openSession(duration: 60, grant: "token")

            for await snapshot in sut.$snapshot.values where snapshot.pluginIDs.contains(flagsID) {
                break
            }
            #expect(listed.serves("Shop.LogLevel"))
            #expect(sut.snapshot.pluginIDs == [flagsID])
        }

        @Test("A relay the sidecar made neither listens nor relays until started, even with a session open in the app")
        func offUntilStarted() async throws {
            let suite = temporarySuiteName("SidecarRelayTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarRelayTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: FakeFlagService(), defaults: defaults)))
            try receiver.start()
            defer { receiver.stop() }
            sessions.perform(.open(duration: 60))
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let connection = try DebugDrawerSidecarConnection(app: listed)
            defer { connection.close() }
            let listener = FakeConnectionListener()

            let sut = DebugDrawerSidecarRelay(connection: connection, timer: ManualSessionTimer()) { registry in
                DebugDrawerNetworkServer(registry: registry, configuration: .init(), listener: listener)
            }

            for await sessionsRead in connection.$sessions.values where sessionsRead != nil {
                break
            }
            for await state in try #require(connection.sessions).snapshots() where state.isActive {
                break
            }
            #expect(listener.requests.isEmpty)
            #expect(sut.server.isRunning == false)
            #expect(sut.snapshot.isRelaying == false)
            #expect(sut.snapshot.pluginIDs.isEmpty)
        }

        @Test("Started, the relay serves the open session; stopped, it serves nothing and stops listening")
        func stopEndsTheRelay() async throws {
            let suite = temporarySuiteName("SidecarRelayTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarRelayTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: FakeFlagService(), defaults: defaults)))
            try receiver.start()
            defer { receiver.stop() }
            sessions.perform(.open(duration: 60))
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let connection = try DebugDrawerSidecarConnection(app: listed)
            defer { connection.close() }
            let listener = FakeConnectionListener()
            let sut = DebugDrawerSidecarRelay(connection: connection, timer: ManualSessionTimer()) { registry in
                DebugDrawerNetworkServer(registry: registry, configuration: .loopback, listener: listener)
            }
            try await sut.start()
            for await snapshot in sut.$snapshot.values where snapshot.pluginIDs.contains(flagsID) {
                break
            }

            sut.stop()

            #expect(sut.snapshot.isRelaying == false)
            #expect(sut.snapshot.pluginIDs.isEmpty)
            #expect(listener.cancelCount == 1)
            #expect(sessions.snapshot.isActive)
        }

        @Test("At the session's expiry date the relay stops, even while the app hasn't yet ended the session")
        func expiryStopsTheRelay() async throws {
            let suite = temporarySuiteName("SidecarRelayTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarRelayTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: FakeFlagService(), defaults: defaults)))
            try receiver.start()
            defer { receiver.stop() }
            sessions.perform(.open(duration: 60))
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let connection = try DebugDrawerSidecarConnection(app: listed)
            defer { connection.close() }
            let timer = ManualSessionTimer()
            let sut = DebugDrawerSidecarRelay(connection: connection, timer: timer) { registry in
                DebugDrawerNetworkServer(registry: registry, configuration: .loopback, listener: FakeConnectionListener())
            }
            try await sut.start()
            for await snapshot in sut.$snapshot.values where snapshot.pluginIDs.contains(flagsID) {
                break
            }
            let expected = sessions.snapshot.session?.expires

            let scheduled = timer.scheduled
            timer.fire()

            #expect(scheduled == expected)
            #expect(sut.snapshot.isRelaying == false)
            #expect(sut.snapshot.pluginIDs.isEmpty)
            #expect(sessions.snapshot.isActive)
        }

        @Test("Without the relay modifier the app's screen has no Mac Viewer control; with it, the control shows, not sharing")
        func macViewerOnlyWhenTurnedOn() throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarRelayTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let receiver = DebugDrawerReceiver(directory: store, sessions: DebugDrawerSessions(maximumDuration: 300))
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.model(LevelModel(), id: "Shop.LogLevel", scope: .persistent))
            try receiver.start()
            defer { receiver.stop() }
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let connection = try DebugDrawerSidecarConnection(app: listed)
            defer { connection.close() }
            let settings = SidecarRelaySettings(configuration: .loopback, startsServing: false)

            let off = SidecarConnectedScreen(connection: connection, plugins: [], layout: .picker, sessionDuration: 60, grant: nil)
            let on = SidecarRelayHost(connection: connection, settings: settings, layout: .picker)

            #expect(throws: (any Error).self) { try off.inspect().find(text: "Mac Viewer: not sharing") }
            #expect(throws: Never.self) { try on.inspect().find(text: "Mac Viewer: not sharing") }
        }

        @Test("The relay's status line says what it shares: nothing while not sharing, the codes waited for, Macs paired, a session's plugins")
        func statusLine() throws {
            let idle = DebugDrawerSidecarRelay.Snapshot(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            var relaying = idle
            relaying.sessionExpires = Date(timeIntervalSinceReferenceDate: 800_000_000)
            relaying.pluginIDs = ["DebugDrawer.FeatureFlagOverrides", "DebugDrawer.Tweaks"]
            let expected = [
                "Mac Viewer: not sharing",
                "Mac Viewer: 0 Macs paired, nothing shared until a session opens",
                "Mac Viewer: 1 waiting for a code, 1 Mac paired, sharing 2 plugins in this session"
            ]

            let actual = try [
                SidecarRelayStatusLine(isServing: false, waiting: 0, paired: 0, snapshot: idle),
                SidecarRelayStatusLine(isServing: true, waiting: 0, paired: 0, snapshot: idle),
                SidecarRelayStatusLine(isServing: true, waiting: 1, paired: 1, snapshot: relaying)
            ].map { try $0.inspect().find(ViewType.Text.self).string() }

            #expect(actual == expected)
        }

        @Test("A snapshot of every JSON kind crosses the relay's value as the same bytes, and decodes as the same value")
        func jsonValueRoundTrips() throws {
            let expected = EveryKind(
                count: 42, largest: .max, smallest: .min, ratio: 0.1, isOn: true, name: "Shöp \"quoted\" \n",
                date: Date(timeIntervalSinceReferenceDate: 800_000_000.25), bytes: Data([0, 1, 254, 255]), missing: nil,
                nested: ["a": [1, 2], "b": []], values: [.integer(3), .double(3), .bool(false), .string("pro")]
            )
            let payload = try TransportMessage.payload(expected)

            let value = try JSONDecoder().decode(JSONValue.self, from: payload)
            let carried = try TransportMessage.payload(value)

            let actual = try JSONDecoder().decode(EveryKind.self, from: carried)
            #expect(carried == payload)
            #expect(actual == expected)
        }

        @Test("JSON kinds decode as their own case: true is a Boolean, 1 an integer, 1.5 a number, beyond Int64 an unsigned integer")
        func jsonValueKinds() throws {
            let text = #"[null,true,1,1.5,18446744073709551615,"1",[],{}]"#
            let expected: [JSONValue] = [
                .null, .bool(true), .integer(1), .number(1.5), .unsignedInteger(.max), .string("1"), .array([]), .object([:])
            ]

            let actual = try JSONDecoder().decode([JSONValue].self, from: Data(text.utf8))

            #expect(actual == expected)
        }
    }
#endif
