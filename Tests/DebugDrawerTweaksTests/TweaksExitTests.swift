// Exit tests start a child process, which only the Mac's test runs can do.
#if os(macOS) && DEBUG
    @testable import DebugDrawerReceiver
    import DebugDrawerTestSupport
    @testable import DebugDrawerTweaks
    import Foundation
    import Testing

    // That a session-scoped tweak survives a kill of the process, so only the next launch can put it
    // back, and does: the receiver's record of unreverted changes, in the store, outlives the
    // process as the defaults do.
    @Suite
    struct TweaksExitTests {
        @Test("A session-scoped tweak changed in a session survives the app being killed during it, and the next launch resets it")
        @MainActor
        func sessionTweakSurvivesKill() async throws {
            let suite = temporarySuiteName("TweaksExitTests")
            let directory = FileManager.default.temporaryDirectory.appending(path: "TweaksExitTests-\(UUID().uuidString)")
            defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }

            await #expect(processExitsWith: .signal(SIGKILL)) { [suite = suite as String, path = directory.path as String] in
                await MainActor.run {
                    guard let defaults = UserDefaults(suiteName: suite) else { return }
                    let backend = Tweak.picker("Backend", key: "backend", default: Server.production).productionSafe()
                    let store = TweakStore(storage: UserDefaultsTweakStorage(defaults: defaults), reading: .offeredProductionSafeTweaks)
                    let sessions = DebugDrawerSessions(maximumDuration: 300)
                    let receiver = DebugDrawerReceiver(directory: URL(filePath: path), sessions: sessions)
                    let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
                    guard (try? receiver.enable(.tweaks([AnyTweak(backend)], store: store, scope: .session(revertWith: .resetAll)))) != nil,
                          layout.create(),
                          let payload = try? TransportMessage.payload(TweaksModel.Command.setValue(key: "backend", value: .string("local"))),
                          let document = try? StoreDocument(TransportMessage(kind: .command, pluginID: TweaksModel.pluginID, payload: payload))
                          .encoded(),
                          (try? layout.write(document, to: layout.commands.appending(path: "0.json"))) != nil
                    else { return }
                    sessions.perform(.open(duration: 60))
                    try? receiver.start()
                    // Killed with the session open and the backend set: no revert can run.
                    kill(getpid(), SIGKILL)
                }
            }
            let defaults = try #require(UserDefaults(suiteName: suite))
            let key = UserDefaultsTweakStorage.defaultKeyPrefix + "backend"
            let leftByKill = defaults.string(forKey: key)
            let backend = Tweak.picker("Backend", key: "backend", default: Server.production).productionSafe()
            let store = TweakStore(storage: UserDefaultsTweakStorage(defaults: defaults), reading: .offeredProductionSafeTweaks)
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
            let expectedEvents: [DebugDrawerAuditEntry.Event] = [.changeReverted]

            try sut.enable(.tweaks([AnyTweak(backend)], store: store, scope: .session(revertWith: .resetAll)))

            let actual: Server = store.value(of: backend)
            #expect(leftByKill == "local")
            #expect(defaults.object(forKey: key) == nil)
            #expect(actual == .production)
            #expect(sessions.auditLog.map(\.event) == expectedEvents)
            #expect(sessions.auditLog.map(\.capability) == [TweaksModel.pluginID])
        }
    }
#endif
