#if DEBUG && os(macOS)
    import Combine
    import DebugDrawer
    import Foundation
    import Testing

    // The keeper made with core's socket server, through the real server and a real socket
    // transport, on the Mac, where the keeper's request is a ProcessInfo activity (the iOS family's
    // UIKit background task needs an app, which a test runner isn't). Each wait is for the event
    // the step produces: the request changing.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct BackgroundKeeperSocketTests {
        @Test(
            "The last sidecar disconnecting from the socket ends its session and lets the activity go; the app stopping its server doesn't",
            arguments: ["disconnect", "stop"]
        )
        func sidecarDisconnects(cause: String) async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "BackgroundKeeperSocketTests-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let socketPath = directory.appending(path: "drawer.sock").path
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let server = DebugDrawerSocketServer(registry: DebugDrawerModelRegistry(sessions: sessions), socketPath: socketPath)
            let sut = DebugDrawerBackgroundKeeper(sessions: sessions, socketServer: server, continuedProcessingIdentifierPrefix: nil)
            var disconnections = 0
            let counting = server.viewerDisconnections.sink { disconnections += 1 }

            try server.start()
            let sidecar = try DebugDrawerSocketTransport(socketPath: socketPath)
            let session = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            session.send(.open(duration: 60))
            for await request in sut.$request.values where request == .activity {
                break
            }
            if cause == "disconnect" {
                sidecar.close()
                for await request in sut.$request.values where request == .none {
                    break
                }
            } else {
                server.stop()
            }

            if cause == "disconnect" {
                #expect(sessions.snapshot == .inactive)
                #expect(sessions.auditLog.last?.event == .sessionEnded(.ended))
                #expect(disconnections == 1)
                #expect(server.viewerCount == 0)
            } else {
                #expect(sessions.snapshot.isActive)
                #expect(sut.request == .activity)
                #expect(disconnections == 0)
            }
            counting.cancel()
            server.stop()
            sessions.end()
        }
    }
#endif
