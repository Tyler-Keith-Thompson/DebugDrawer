#if DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerTweaks
    import Foundation
    import Testing

    // The tweaks capability as a sidecar reaches it in a production app: a real receiver over the
    // app group's store, driven by the sidecar's own store transport. Each store reads as a
    // release build does (`.offeredProductionSafeTweaks`), so what the app's accessor returns here
    // is what it returns in release; the shared store `Tweak.value` reads is left alone, as other
    // suites read it. Refusals are awaited through the sessions' audit entries.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct TweaksReceiverTests {
        private let backend = Tweak.picker("Backend", key: "backend", default: Server.production).productionSafe()
        private let timeout = Tweak.stepper("Timeout", key: "timeout", default: 30, in: 5 ... 120, step: 5).productionSafe()
        private let verbose = Tweak.toggle("Verbose logging", key: "verbose", default: false)
        private let apiToken = Tweak.text("API token", key: "apiToken", default: "")

        @Test("A sidecar's snapshot lists only the production-safe tweaks, with their controls, defaults and the values the app reads")
        func snapshotListsOnlyProductionSafe() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "TweaksReceiverTests-\(UUID().uuidString)")
            let storage = FakeTweakStorage(["timeout": .int(60), "verbose": .bool(true), "apiToken": .string("t0k3n")])
            let store = TweakStore(storage: storage, reading: .offeredProductionSafeTweaks)
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.tweaks([AnyTweak(backend), AnyTweak(verbose), AnyTweak(timeout), AnyTweak(apiToken)], store: store, scope: .persistent))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let expected = TweaksModel.Snapshot(tweaks: [
                TweaksModel.Entry(
                    title: "Backend",
                    key: "backend",
                    control: .picker([
                        TweakOption(title: "production", value: .string("production")),
                        TweakOption(title: "staging", value: .string("staging")),
                        TweakOption(title: "local", value: .string("local"))
                    ]),
                    defaultValue: .string("production"),
                    value: .string("production")
                ),
                TweaksModel.Entry(
                    title: "Timeout", key: "timeout", control: .stepper(range: 5 ... 120, step: 5), defaultValue: .int(30), value: .int(60)
                )
            ])

            let sut = try await sidecar.connect(

                toPlugin: TweaksModel.pluginID, snapshot: TweaksModel.Snapshot.self, command: TweaksModel.Command.self

            )

            #expect(sut.snapshot == expected)
            #expect(receiver.enabledCapabilities == [TweaksModel.pluginID])
        }

        @Test("Inside a session, a command to a tweak not marked production-safe is refused as not exposed, audited, and changes nothing")
        func unmarkedTweakRefusedInsideSession() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "TweaksReceiverTests-\(UUID().uuidString)")
            let storage = FakeTweakStorage()
            let store = TweakStore(storage: storage, reading: .offeredProductionSafeTweaks)
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.tweaks([AnyTweak(backend), AnyTweak(verbose), AnyTweak(apiToken)], store: store, scope: .persistent))
            try receiver.start()
            defer { receiver.stop() }
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let session = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let sut = try await sidecar.connect(
                toPlugin: TweaksModel.pluginID, snapshot: TweaksModel.Snapshot.self, command: TweaksModel.Command.self
            )
            let expectedEvents: [DebugDrawerAuditEntry.Event] = [
                .commandRefused(.notExposed),
                .commandRefused(.notExposed),
                .commandRefused(.notExposed),
                .commandApplied
            ]
            let expectedStored: [String: TweakStoredValue] = ["backend": .string("staging")]

            session.send(.open(duration: 60))
            sut.send(.setValue(key: "verbose", value: .bool(true)))
            sut.send(.setValue(key: "apiToken", value: .string("stolen")))
            sut.send(.reset(key: "apiToken"))
            sut.send(.setValue(key: "backend", value: .string("staging")))
            var actual: [DebugDrawerAuditEntry] = []
            for await entry in arrivals {
                actual.append(entry)
                if actual.count == expectedEvents.count + 1 {
                    break
                }
            }

            let opened = try #require(actual.first)
            let openedSession = try #require(opened.sessionID)
            let commands = actual.dropFirst()
            #expect(opened.capability == DebugDrawerSessions.pluginID)
            #expect(commands.allSatisfy { $0.sessionID == openedSession && $0.capability == TweaksModel.pluginID })
            #expect(commands.map(\.event) == expectedEvents)
            #expect(storage.values == expectedStored)
            #expect(store.value(of: verbose) == false)
            #expect(store.value(of: apiToken).isEmpty)
        }

        @Test("A value that isn't one of the tweak's values is refused as malformed, audited, and changes nothing")
        func valueOutsideTweakRefused() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "TweaksReceiverTests-\(UUID().uuidString)")
            let storage = FakeTweakStorage()
            let store = TweakStore(storage: storage, reading: .offeredProductionSafeTweaks)
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.tweaks([AnyTweak(backend), AnyTweak(timeout)], store: store, scope: .persistent))
            sessions.perform(.open(duration: 60))
            try receiver.start()
            defer { receiver.stop() }
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sut = try await sidecar.connect(
                toPlugin: TweaksModel.pluginID, snapshot: TweaksModel.Snapshot.self, command: TweaksModel.Command.self
            )
            let expected: [DebugDrawerAuditEntry.Event] = Array(repeating: .commandRefused(.malformedCommand), count: 3)

            sut.send(.setValue(key: "backend", value: .string("qa")))
            sut.send(.setValue(key: "backend", value: .bool(true)))
            sut.send(.setValue(key: "timeout", value: .int(500)))
            var actual: [DebugDrawerAuditEntry.Event] = []
            for await entry in arrivals {
                actual.append(entry.event)
                if actual.count == expected.count {
                    break
                }
            }

            #expect(actual == expected)
            #expect(storage.values.isEmpty)
        }

        @Test("A sidecar's value persists in the tweaks' storage and reaches the app's typed accessor, before and after a relaunch")
        func valuePersistsAcrossRelaunch() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "TweaksReceiverTests-\(UUID().uuidString)")
            let suiteName = "com.debugdrawer.tests.tweaks-receiver.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suiteName))
            defer { defaults.removePersistentDomain(forName: suiteName) }
            let firstStore = TweakStore(storage: UserDefaultsTweakStorage(defaults: defaults), reading: .offeredProductionSafeTweaks)
            let firstSessions = DebugDrawerSessions(maximumDuration: 300)
            let firstLaunch = DebugDrawerReceiver(directory: directory, sessions: firstSessions)
            firstLaunch.enable(.tweaks([AnyTweak(backend), AnyTweak(timeout)], store: firstStore, scope: .persistent))
            try firstLaunch.start()
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let session = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let tweaks = try await sidecar.connect(
                toPlugin: TweaksModel.pluginID, snapshot: TweaksModel.Snapshot.self, command: TweaksModel.Command.self
            )
            session.send(.open(duration: 60))
            tweaks.send(.setValue(key: "backend", value: .string("staging")))
            tweaks.send(.setValue(key: "timeout", value: .int(90)))
            for await snapshot in tweaks.snapshots() where snapshot.tweaks.map(\.value) == [.string("staging"), .int(90)] {
                break
            }
            let firstBackend: Server = firstStore.value(of: backend)
            let firstTimeout: Int = firstStore.value(of: timeout)
            firstSessions.end()
            firstLaunch.stop()

            let relaunchedDefaults = try #require(UserDefaults(suiteName: suiteName))
            let sut = TweakStore(storage: UserDefaultsTweakStorage(defaults: relaunchedDefaults), reading: .offeredProductionSafeTweaks)
            let relaunch = DebugDrawerReceiver(directory: directory, sessions: DebugDrawerSessions(maximumDuration: 300))
            relaunch.enable(.tweaks([AnyTweak(backend), AnyTweak(timeout)], store: sut, scope: .persistent))
            try relaunch.start()
            defer { relaunch.stop() }

            let actualBackend: Server = sut.value(of: backend)
            let actualTimeout: Int = sut.value(of: timeout)
            #expect(firstBackend == .staging)
            #expect(firstTimeout == 90)
            #expect(actualBackend == .staging)
            #expect(actualTimeout == 90)
            #expect(relaunchedDefaults.string(forKey: UserDefaultsTweakStorage.defaultKeyPrefix + "backend") == "staging")
        }

        @Test("With the session scope, ending the session resets the production-safe tweaks and audits the revert")
        func sessionScopeResets() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "TweaksReceiverTests-\(UUID().uuidString)")
            let storage = FakeTweakStorage(["verbose": .bool(true)])
            let store = TweakStore(storage: storage, reading: .offeredProductionSafeTweaks)
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            receiver.enable(.tweaks([AnyTweak(backend), AnyTweak(verbose)], store: store, scope: .session(revertWith: .resetAll)))
            sessions.perform(.open(duration: 60))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sut = try await sidecar.connect(
                toPlugin: TweaksModel.pluginID, snapshot: TweaksModel.Snapshot.self, command: TweaksModel.Command.self
            )
            sut.send(.setValue(key: "backend", value: .string("local")))
            for await snapshot in sut.snapshots() where snapshot.tweaks.first?.value == .string("local") {
                break
            }
            let changed: Server = store.value(of: backend)
            let expectedTail: [DebugDrawerAuditEntry.Event] = [.changeReverted, .sessionEnded(.ended)]
            let expectedStored: [String: TweakStoredValue] = ["verbose": .bool(true)]

            sessions.end()

            let actual: Server = store.value(of: backend)
            #expect(changed == .local)
            #expect(actual == .production)
            #expect(Array(sessions.auditLog.suffix(2).map(\.event)) == expectedTail)
            #expect(storage.values == expectedStored)
        }
    }
#endif
