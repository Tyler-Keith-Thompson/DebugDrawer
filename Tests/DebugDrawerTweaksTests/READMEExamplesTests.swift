// The README's production tweaks example, verbatim, so the README cannot drift from the code.
#if DEBUG
    import DebugDrawer
    import DebugDrawerReceiver
    import DebugDrawerTweaks
    import Foundation
    import Testing

    enum Backend: String, CaseIterable {
        case production, staging, local
    }

    enum AppTweaks {
        static let backend = Tweak.picker("Backend", key: "backend", default: Backend.production).productionSafe()
        static let newCheckout = Tweak.toggle("New checkout", key: "newCheckout", default: false)
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test("Production builds: tweaks: in a session, a sidecar sees the production-safe tweak and not the other", .timeLimit(.minutes(1)))
        func productionTweaks() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "READMETweaks-\(UUID().uuidString)")
            let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
            let receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)

            receiver.enable(.tweaks(AppTweaks.backend, AppTweaks.newCheckout))

            try receiver.start()
            defer { receiver.stop() }
            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))
            sessions.perform(.open(duration: 60))
            defer { sessions.end() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: appDirectory)
            let tweaks = try await sidecar.connect(
                toPlugin: TweaksModel.pluginID, snapshot: TweaksModel.Snapshot.self, command: TweaksModel.Command.self
            )
            #expect(tweaks.snapshot.tweaks.map(\.key) == ["backend"])
        }
    }
#endif
