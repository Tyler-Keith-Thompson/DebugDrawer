// The app state capability as a sidecar reaches it: a real DebugDrawerReceiver serving the
// app-group store, and the sidecar's DebugDrawerAppGroupStoreTransport (a debug-build type) reading
// it from the same directory, opening sessions through the sessions' own model.
#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerAppInfo
    @testable import DebugDrawerReceiver
    import DebugDrawerTestSupport
    import Foundation
    #if os(macOS)
        import OSLog
    #endif
    import Testing

    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct AppStateSidecarTests {
        @Test("The sidecar sees the state during its session, the registered fields with it, and nothing of it is in the store before or after")
        func servedDuringSession() async throws {
            let suite = temporarySuiteName("AppStateSidecarTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let root = FileManager.default.temporaryDirectory.appending(path: "AppStateSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let environments = try DebugDrawerEnvironments(
                default: DebugDrawerEnvironment("production", title: "Production"),
                allowing: DebugDrawerEnvironment("staging", title: "Staging"),
                adapter: FakeBackend(), defaults: defaults
            )
            let appState = try DebugDrawerAppState(
                sessions: sessions, buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1"), environments: environments,
                values: [DebugDrawerAppStateField("plan") { "pro" }], defaults: defaults
            )
            receiver.enable(.appState(appState))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: DebugDrawerAppState.pluginID)
            let expectedValues: [String: DebugDrawerAppStateValue] = ["plan": "pro"]

            let servedBeforeSession = FileManager.default.fileExists(atPath: snapshotFile.path)
            sessionControl.send(.open(duration: 60))
            // Served once the session is open.
            let state = try await sidecar.connect(
                toPlugin: DebugDrawerAppState.pluginID, snapshot: DebugDrawerAppState.Snapshot.self, command: DebugDrawerAppState.Command.self
            )
            var arrivals = state.snapshots().makeAsyncIterator()
            var during: DebugDrawerAppState.Snapshot?
            while let snapshot = await arrivals.next() {
                if snapshot.state != nil {
                    during = snapshot
                    break
                }
            }
            sessionControl.send(.end)
            for await state in sessionControl.snapshots() where !state.isActive {
                break
            }
            let servedAfterSession = FileManager.default.fileExists(atPath: snapshotFile.path)

            #expect(!servedBeforeSession)
            #expect(during?.state?.buildMetadata.gitCommit == "4f9c2e1")
            #expect(during?.state?.environment?.id == "production")
            #expect(during?.state?.values == expectedValues)
            #expect(during?.state?.featureFlagOverrides == nil)
            #expect(!servedAfterSession)
        }

        @Test("The raw user ID is never written: not to the store's files, the snapshots received, the audit log, the defaults or the log")
        func rawUserIDNeverLeaves() async throws {
            let started = Date()
            let suite = temporarySuiteName("AppStateSidecarTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let root = FileManager.default.temporaryDirectory.appending(path: "AppStateSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let rawID = "cust-7Q2X-9941-jane"
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let appState = try DebugDrawerAppState(sessions: sessions, userID: { rawID }, defaults: defaults)
            receiver.enable(.appState(appState))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            var received: [DebugDrawerAppState.Snapshot] = []
            sessionControl.send(.open(duration: 60))
            // Served once the session is open.
            let state = try await sidecar.connect(
                toPlugin: DebugDrawerAppState.pluginID, snapshot: DebugDrawerAppState.Snapshot.self, command: DebugDrawerAppState.Command.self
            )
            var arrivals = state.snapshots().makeAsyncIterator()
            while let snapshot = await arrivals.next() {
                received.append(snapshot)
                if snapshot.state != nil {
                    break
                }
            }
            state.send(.refresh)
            let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: DebugDrawerAppState.pluginID)
            let raw = Data(rawID.utf8)

            /// The ID's spellings that could reach a file: as it is, either case, its bytes in
            /// hexadecimal either case, and its base64 and base64url.
            func holdsID(_ data: Data) -> Bool {
                let hexadecimal = raw.map { String(format: "%02x", $0) }.joined()
                let base64 = raw.base64EncodedString()
                let base64URL = base64.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                    .trimmingCharacters(in: CharacterSet(charactersIn: "="))
                let spellings = [rawID, rawID.lowercased(), rawID.uppercased(), hexadecimal, hexadecimal.uppercased(), base64, base64URL]
                return spellings.contains { data.range(of: Data($0.utf8)) != nil }
            }
            /// What a store document's payload holds, which the store base64-encodes inside it.
            func payload(of file: URL) -> Data? {
                (try? Data(contentsOf: file)).flatMap(StoreDocument.decoded(from:))?.message.payload
            }
            /// Every regular file under `directory` written since the test started.
            func filesWritten(under directory: URL) -> [URL] {
                let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
                guard let walk = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return [] }
                return walk.compactMap { $0 as? URL }.filter { file in
                    guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return false }
                    return (values.contentModificationDate ?? .distantPast) >= started.addingTimeInterval(-1)
                }
            }
            let duringSession = try #require(payload(of: snapshotFile))
            // The test runners give the process a home folder of its own in a temporary folder
            // (CFFIXED_USER_HOME), so all of it is searched: the defaults' plists, Application
            // Support, Caches; run without one, only the defaults' plists are. Beside it, everything
            // under this test's own folder, the store included. The system's temporary directory isn't
            // walked: every process on the Mac writes there, and walking it takes seconds.
            let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] != nil
                ? URL.homeDirectory : URL.homeDirectory.appending(path: "Library/Preferences")
            let written = filesWritten(under: home) + filesWritten(under: root)
            let leaks = written.filter { file in
                (try? Data(contentsOf: file)).map(holdsID) == true || payload(of: file).map(holdsID) == true
            }
            let receivedJSON = try JSONEncoder().encode(received)
            let defaultsData = try PropertyListSerialization.data(
                fromPropertyList: defaults.dictionaryRepresentation(), format: .binary, options: 0
            )
            let audit = try JSONEncoder().encode(sessions.auditLog)
            #if os(macOS)
                let logStore = try OSLogStore(scope: .currentProcessIdentifier)
                let logLines = try logStore.getEntries(at: logStore.position(date: started)).compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
                #expect(!logLines.contains { $0.localizedCaseInsensitiveContains(rawID) })
            #endif
            let canary = Data("prefix \(rawID) suffix".utf8)
            let hashed = received.last?.state?.hashedUserID

            #expect(holdsID(canary))
            #expect(!written.isEmpty)
            #expect(leaks.isEmpty, "Written with the raw ID: \(leaks.map(\.path))")
            #expect(!holdsID(duringSession))
            #expect(!holdsID(receivedJSON))
            #expect(!holdsID(defaultsData))
            #expect(!audit.isEmpty)
            #expect(!holdsID(audit))
            #expect(hashed?.count == 64)
            #expect(hashed.map { duringSession.range(of: Data($0.utf8)) != nil } == true)
            sessionControl.send(.end)
        }

        @Test("Until the host enables it, a refresh is refused unknownCapability in an open session, and nothing is served")
        func offUnlessEnabled() throws {
            let suite = temporarySuiteName("AppStateSidecarTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let directory = FileManager.default.temporaryDirectory.appending(path: "AppStateSidecarTests-\(UUID().uuidString)")
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let payloads: [(String, Data)] = try [
                (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                (DebugDrawerAppState.pluginID, TransportMessage.payload(DebugDrawerAppState.Command.refresh))
            ]
            for (index, (id, payload)) in payloads.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
            // A receiver with no capability enabled opens no session, so another one is enabled.
            try sut.enable(.environments(DebugDrawerEnvironments(
                default: DebugDrawerEnvironment("production", title: "Production"),
                allowing: DebugDrawerEnvironment("staging", title: "Staging"),
                adapter: FakeBackend(), defaults: defaults
            )))

            try sut.start()
            defer { sut.stop() }

            let last = try #require(sessions.auditLog.last)
            #expect(sessions.snapshot.isActive)
            #expect(last.capability == DebugDrawerAppState.pluginID)
            #expect(last.event == .commandRefused(.unknownCapability))
            #expect(sut.enabledCapabilities == [DebugDrawerEnvironments.pluginID])
            #expect(!FileManager.default.fileExists(atPath: layout.snapshotFile(for: DebugDrawerAppState.pluginID).path))
        }
    }
#endif
