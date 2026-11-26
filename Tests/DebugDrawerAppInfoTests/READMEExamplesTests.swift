// The README's production app state example, verbatim, so the README cannot drift from the code.
#if DEBUG
    import DebugDrawer
    import DebugDrawerAppInfo
    import DebugDrawerReceiver
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @MainActor
    final class Account {
        var userID: String?
        var plan = "free"
    }

    @MainActor
    final class ProductionAppStateSnapshot {
        let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
        let appState: DebugDrawerAppState
        let receiver: DebugDrawerReceiver

        init(flags: DebugDrawerFeatureFlagOverrides, account: Account, container: URL) throws {
            appState = try DebugDrawerAppState(
                sessions: sessions,
                featureFlags: flags,
                userID: { account.userID },
                values: [DebugDrawerAppStateField("plan") { .string(account.plan) }]
            )
            receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
            receiver.enable(.featureFlagOverrides(flags))
            receiver.enable(.appState(appState))
            try receiver.start()
        }
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test(
            "Production builds: the app's state: served under its ID once a session opens, with the build, overrides, hashed ID and plan",
            .timeLimit(.minutes(1))
        )
        func productionAppState() async throws {
            let suite = temporarySuiteName("READMEAppState")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let container = FileManager.default.temporaryDirectory.appending(path: "READMEAppState-\(UUID().uuidString)")
            let flags = DebugDrawerFeatureFlagOverrides(adapter: FakeFlagService(["new-checkout": .bool(false)]), defaults: defaults)
            let account = Account()
            account.userID = "user-42"
            account.plan = "pro"
            let production = try ProductionAppStateSnapshot(flags: flags, account: account, container: container)
            defer { production.receiver.stop() }
            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))
            let snapshotFile = AppGroupStoreLayout(directory: appDirectory).snapshotFile(for: DebugDrawerAppState.pluginID)
            let expectedEnabled = [DebugDrawerAppState.pluginID, DebugDrawerFeatureFlagOverrides.pluginID]
            let expectedValues: [String: DebugDrawerAppStateValue] = ["plan": "pro"]

            let servedBeforeSession = FileManager.default.fileExists(atPath: snapshotFile.path)
            production.sessions.perform(.open(duration: 60))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: appDirectory)
            _ = try await sidecar.connect(
                toPlugin: DebugDrawerAppState.pluginID, snapshot: DebugDrawerAppState.Snapshot.self, command: DebugDrawerAppState.Command.self
            )
            flags.perform(.setOverride(key: "new-checkout", value: .bool(true)))
            let during = production.appState.snapshot.state

            #expect(production.receiver.enabledCapabilities.sorted() == expectedEnabled)
            #expect(!servedBeforeSession)
            #expect(during?.featureFlagOverrides == ["new-checkout": .bool(true)])
            #expect(during?.values == expectedValues)
            #expect(during?.hashedUserID?.count == 64)
            production.sessions.end()
        }
    }
#endif
