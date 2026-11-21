#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    /// A model a receiver serves, so it has a capability to list.
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

    // A production app's receiver serves a capability only within a session (DD-271), so the kit's
    // plugin host says so in place of the plugin while no session is open, or while the open one's
    // grant doesn't list it. The gate's view takes what the session lets the sidecar read; what that
    // is comes from the sessions' state; and the presence file says which apps serve this way.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarSessionGateTests {
        private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

        @Test("No session, or none read yet, lets the sidecar see nothing; a session without a grant, or whose grant lists the plugin, lets it")
        func readingFromState() {
            let session = DebugDrawerSession(id: UUID(), opened: Self.now, expires: Self.now.addingTimeInterval(60))
            let grant = DebugDrawerGrant(
                id: "g-1", subject: "tester@example.com", audiences: ["com.example.shop"], capabilities: ["DebugDrawer.Tweaks"],
                notBefore: Self.now, expires: Self.now.addingTimeInterval(60)
            )
            let granted = DebugDrawerSession(id: UUID(), opened: Self.now, expires: Self.now.addingTimeInterval(60), grant: grant)
            let expected: [SidecarSessionReading] = [.noSession, .noSession, .reading, .reading, .notGranted]

            let actual = [
                SidecarSessionReading(state: nil, pluginID: "DebugDrawer.Tweaks"),
                SidecarSessionReading(state: .inactive, pluginID: "DebugDrawer.Tweaks"),
                SidecarSessionReading(state: .active(session), pluginID: "DebugDrawer.Tweaks"),
                SidecarSessionReading(state: .active(granted), pluginID: "DebugDrawer.Tweaks"),
                SidecarSessionReading(state: .active(granted), pluginID: "DebugDrawer.FeatureFlagOverrides")
            ]

            #expect(actual == expected)
        }

        @Test("With no session the gate asks for one, naming the plugin, and draws none of the plugin")
        func noSessionAsksForOne() throws {
            let sut = SidecarSessionGate(reading: .noSession, title: "Flags") { Text("new-checkout") }

            let inspected = try sut.inspect()

            #expect(throws: Never.self) { try inspected.find(text: "No Session") }
            #expect(throws: Never.self) { try inspected.find(text: "Open a session to see Flags.") }
            #expect(throws: (any Error).self) { try inspected.find(text: "new-checkout") }
        }

        @Test("With a session whose grant doesn't list the plugin the gate says so, and draws none of the plugin")
        func notGrantedSaysSo() throws {
            let sut = SidecarSessionGate(reading: .notGranted, title: "Flags") { Text("new-checkout") }

            let inspected = try sut.inspect()

            #expect(throws: Never.self) { try inspected.find(text: "Not Granted") }
            #expect(throws: Never.self) { try inspected.find(text: "This session's grant doesn't list Flags.") }
            #expect(throws: (any Error).self) { try inspected.find(text: "new-checkout") }
        }

        @Test("With a session that may read it, the gate draws the plugin")
        func readingDrawsThePlugin() throws {
            let sut = SidecarSessionGate(reading: .reading, title: "Flags") { Text("new-checkout") }

            let inspected = try sut.inspect()

            #expect(throws: Never.self) { try inspected.find(text: "new-checkout") }
            #expect(throws: (any Error).self) { try inspected.find(text: "No Session") }
        }

        @Test("A receiver's app is listed as serving only within sessions; a debug store server's isn't")
        func presenceSaysWhoServesInSessions() throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarSessionGateTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let receiver = DebugDrawerReceiver(directory: store, sessions: DebugDrawerSessions(maximumDuration: 60))
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.model(LevelModel(), id: "Shop.LogLevel", scope: .persistent))
            try receiver.start()
            defer { receiver.stop() }
            let debugDirectory = AppGroupStoreLayout.appDirectory(of: "com.example.shop.debug", inStore: store)
            try FileManager.default.createDirectory(at: debugDirectory, withIntermediateDirectories: true)
            let debugPresence = AppPresence(
                identity: AppPresence.Identity(bundleIdentifier: "com.example.shop.debug", displayName: "Shop Debug", version: "2.5", build: "900"),
                capabilities: ["ConsolePlugin"], lastSeen: Self.now
            )
            try debugPresence.encoded().write(to: AppPresence.file(inAppDirectory: debugDirectory))

            let apps = DebugDrawerSidecarAppList(storeDirectory: store).apps

            let actual = apps.map { "\($0.bundleIdentifier) \($0.servesInSessionsOnly)" }.sorted()
            #expect(actual == ["com.example.shop true", "com.example.shop.debug false"])
        }
    }
#endif
