#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing

    /// A model a receiver serves, so a session has something to drive.
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

    // The kit's session control against a production app's receiver over the store, in a temporary
    // group store: the kit reads the sessions as the app lists them, opens one and ends it. Each
    // wait is for the sessions' snapshot the step should produce.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarSessionTests {
        @Test("The kit reads a receiver's sessions, opens one for the duration asked, capped by the app, and ends it")
        func opensAndEndsASession() async throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarSessionTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 60)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.model(LevelModel(), id: "Shop.LogLevel", scope: .persistent))
            try receiver.start()
            let app = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let sut = try DebugDrawerSidecarConnection(app: app)
            var read: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>?
            for await transport in sut.$sessions.values where transport != nil {
                read = transport
                break
            }
            let transport = try #require(read)
            let before = transport.snapshot

            sut.openSession(duration: 10 * 60)
            for await state in transport.snapshots() where state.isActive {
                break
            }
            let opened = try #require(transport.snapshot.session)
            sut.endSession()
            for await state in transport.snapshots() where !state.isActive {
                break
            }

            #expect(app.requiresSession)
            #expect(before == .inactive)
            #expect(opened.expires.timeIntervalSince(opened.opened) == 60)
            #expect(sessions.snapshot == .inactive)
            sut.close()
            receiver.stop()
        }

        @Test("An app whose commands act at once has no sessions to read")
        func noSessionsForAnUngatedApp() throws {
            let app = DebugDrawerSidecarApp(
                bundleIdentifier: "com.example.shop.debug", displayName: "Shop Debug", version: "2.5", build: "900",
                capabilities: ["ConsolePlugin"], protocolVersion: 2, lastSeen: Date(),
                storeDirectory: FileManager.default.temporaryDirectory.appending(path: "SidecarSessionTests-\(UUID().uuidString)")
            )

            let sut = try DebugDrawerSidecarConnection(app: app)
            sut.openSession(duration: 60)

            #expect(!app.requiresSession)
            #expect(sut.sessions == nil)
            #expect(app.socketPath.hasSuffix("/drawer.sock"))
            sut.close()
        }
    }
#endif
