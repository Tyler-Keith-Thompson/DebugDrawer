#if DEBUG && os(macOS)
    import DebugDrawer
    import DebugDrawerAppInfo
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    // The kit's App State plugin over a production app's receiver: the state shown, Refresh sent,
    // and `app-state.json` in Create Report whether or not the plugin was opened. Each wait is for
    // the snapshot or file that step should produce, never for time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarAppStateTests {
        @Test("Hosted as the app connects, the app state is in Create Report as app-state.json, its user ID hashed and masked keys redacted")
        func attachedToEveryReport() async throws {
            let suite = "SidecarAppStateTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarAppStateTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let rawID = "cust-4410-sam"
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let appState = DebugDrawerAppState(
                sessions: sessions, buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1"), userID: { rawID },
                values: [DebugDrawerAppStateField("plan") { "pro" }, DebugDrawerAppStateField("supportToken") { "st-81f2" }],
                defaults: defaults
            )
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.appState(appState))
            try receiver.start()
            defer { receiver.stop() }
            sessions.perform(.open(duration: 60))
            let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: DebugDrawerAppState.pluginID)
            let watcher = try #require(DirectoryWatcher(directory: snapshotFile.deletingLastPathComponent()))
            defer { watcher.cancel() }
            func storedState() -> DebugDrawerAppState.State? {
                guard let data = try? Data(contentsOf: snapshotFile), let document = StoreDocument.decoded(from: data) else { return nil }
                return try? JSONDecoder().decode(DebugDrawerAppState.Snapshot.self, from: document.message.payload).state
            }
            if storedState() == nil {
                for await _ in watcher.changes where storedState() != nil {
                    break
                }
            }
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let sut = try DebugDrawerSidecarConnection(app: listed)
            defer { sut.close() }
            let reports = store.deletingLastPathComponent().appending(path: "Reports")

            await sut.hostOnConnect([.console, .appState])
            let hostedOnConnect = sut.hosted.map(\.title)
            let archive = try sut.createReport(redaction: .standard, in: reports)
            let unzipped = reports.appending(path: "unzipped")
            let unzip = Process()
            unzip.executableURL = URL(filePath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", archive.path, unzipped.path]
            try unzip.run()
            unzip.waitUntilExit()
            let folder = try #require(try FileManager.default.contentsOfDirectory(at: unzipped, includingPropertiesForKeys: nil).first)
            let json = try Data(contentsOf: folder.appending(path: "App State/app-state.json"))
            let state = try JSONSerialization.jsonObject(with: json) as? [String: Any]
            let values = state?["values"] as? [String: Any]
            let metadata = state?["buildMetadata"] as? [String: Any]
            let rawBytes = Data(rawID.utf8)
            let spellings = [rawID, rawBytes.map { String(format: "%02x", $0) }.joined(), rawBytes.base64EncodedString()]

            #expect(hostedOnConnect == ["App State"])
            #expect(sut.hosted.map(\.title) == ["App State"])
            #expect(metadata?["gitCommit"] as? String == "4f9c2e1")
            #expect(values?["plan"] as? String == "pro")
            #expect(values?["supportToken"] as? String == DebugDrawerRedaction.mask)
            #expect((state?["hashedUserID"] as? String)?.count == 64)
            #expect(spellings.allSatisfy { json.range(of: Data($0.utf8)) == nil })
        }

        @Test("The view shows the build, each registered field and Refresh, which sends refresh")
        func showsState() throws {
            let state = DebugDrawerAppState.State(
                bundleIdentifier: "com.example.shop", version: "2.4", build: "881",
                buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1", gitBranch: "main"), date: Date(timeIntervalSince1970: 0),
                featureFlagOverrides: ["new-checkout": .bool(true)],
                experiments: ["checkout-flow": .init(variant: "one-page", isOverridden: true)],
                environment: .init(id: "staging", title: "Staging", isSwitched: true),
                hashedUserID: "9f2c41d0", values: ["cartItems": 3]
            )
            var sent: [DebugDrawerAppState.Command] = []
            let sut = AppStateView(snapshot: DebugDrawerAppState.Snapshot(sessionID: UUID(), state: state)) { sent.append($0) }

            try sut.inspect().find(button: "Refresh").tap()

            #expect(sent == [.refresh])
            for text in ["2.4", "881", "4f9c2e1", "main", "Staging (switched)", "9f2c41d0", "On", "one-page (overridden)", "3"] {
                #expect(throws: Never.self, "\(text)") { try sut.inspect().find(text: text) }
            }
        }

        @Test("With only the build registered, the view shows Build and no other section")
        func standardFieldsOnly() throws {
            let state = DebugDrawerAppState.State(
                bundleIdentifier: "com.example.shop", version: "2.4", build: "881", buildMetadata: AppInfoBuildMetadata(), date: Date()
            )
            let sut = AppStateView(snapshot: DebugDrawerAppState.Snapshot(sessionID: UUID(), state: state)) { _ in }

            #expect(throws: Never.self) { try sut.inspect().find(text: "Build") }
            for title in ["Environment", "User", "Flag Overrides", "Experiments", "Values"] {
                #expect(throws: (any Error).self, "\(title)") { try sut.inspect().find(text: title) }
            }
        }

        @Test("Outside a session the view says so, and the report gets no app state")
        func noSession() throws {
            let suite = "SidecarAppStateTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let appState = DebugDrawerAppState(sessions: DebugDrawerSessions(maximumDuration: 300), defaults: defaults)
            let plugin = AppStatePlugin(transport: .direct(to: appState))
            let sut = AppStateView(snapshot: appState.snapshot) { _ in }
            var report = DebugDrawerReport()

            plugin.contribute(to: &report, redaction: DebugDrawerRedaction())

            #expect(throws: Never.self) { try sut.inspect().find(text: "No App State") }
            #expect(report.files.isEmpty)
        }

        @Test("The kit's App State plugin is the capability's, hosted as the app is reached")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.appState

            #expect([sut.id, sut.title, sut.icon] == [DebugDrawerAppState.pluginID, "App State", "list.bullet.rectangle"])
            #expect(sut.hostsOnConnect)
            #expect(!DebugDrawerSidecarPlugin.console.hostsOnConnect)
        }
    }
#endif
