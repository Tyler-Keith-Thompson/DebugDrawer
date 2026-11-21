// The push registration capability as a sidecar reaches it: a real DebugDrawerReceiver serving the
// app-group store, and the sidecar's DebugDrawerAppGroupStoreTransport (a debug-build type) reading
// it from the same directory, opening sessions through the sessions' own model. The settings come
// from a closure, as a test runner has no notification center.
#if DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerNotifications
    @testable import DebugDrawerReceiver
    import DebugDrawerTestSupport
    import Foundation
    #if os(macOS)
        import OSLog
    #endif
    import Testing

    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct PushRegistrationSidecarTests {
        @Test("The sidecar sees the token, the environment and the authorization status in its session, and none of it is in the store outside it")
        func servedDuringSession() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "PushRegistrationSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let environment = PushEnvironment(server: .sandbox, source: .provisioningProfile)
            let settings = NotificationSettings(authorization: .authorized, items: [.init(name: "Alerts", value: "On")])
            let mirror = PushRegistrationMirror(sessions: sessions, environment: environment, settings: { settings })
            mirror.didRegisterForRemoteNotifications(withDeviceToken: Data([0x7A, 0x00, 0xC3, 0x19]))
            receiver.enable(.pushRegistration(mirror))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: PushRegistrationMirror.pluginID)
            let servedBeforeSession = FileManager.default.fileExists(atPath: snapshotFile.path)

            sessionControl.send(.open(duration: 60))
            // Served once the session is open.
            let push = try await sidecar.connect(
                toPlugin: PushRegistrationMirror.pluginID,
                snapshot: PushRegistrationMirror.Snapshot.self,
                command: PushRegistrationMirror.Command.self
            )
            var arrivals = push.snapshots().makeAsyncIterator()
            var during: PushRegistrationMirror.Snapshot?
            while let snapshot = await arrivals.next() {
                if snapshot.settings != nil {
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
            #expect(during?.sessionID != nil)
            #expect(during?.registration == .registered(deviceToken: "7a00c319"))
            #expect(during?.environment == environment)
            #expect(during?.settings?.authorization == .authorized)
            #expect(during?.settings?.items == [.init(name: "Alerts", value: "On")])
            #expect(!servedAfterSession)
        }

        @Test("The token is written only to the store's snapshot file, never to the audit log, defaults or logs, and leaves it as the session ends")
        func tokenStaysInStore() async throws {
            let started = Date()
            let root = FileManager.default.temporaryDirectory.appending(path: "PushRegistrationSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let token = Data([0xD3, 0x5E, 0x91, 0x0C, 0x44, 0xB7, 0x2A, 0xE8, 0x6F, 0x13, 0xC0, 0x9D, 0x58, 0x07, 0xFA, 0x31])
            let hexadecimal = "d35e910c44b72ae86f13c09d5807fa31"
            let mirror = PushRegistrationMirror(
                sessions: sessions, environment: PushEnvironment(server: .production, source: .host),
                settings: { NotificationSettings(authorization: .denied, items: []) }
            )
            mirror.didRegisterForRemoteNotifications(withDeviceToken: token)
            receiver.enable(.pushRegistration(mirror))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            sessionControl.send(.open(duration: 60))
            // Served once the session is open.
            let push = try await sidecar.connect(
                toPlugin: PushRegistrationMirror.pluginID,
                snapshot: PushRegistrationMirror.Snapshot.self,
                command: PushRegistrationMirror.Command.self
            )
            var arrivals = push.snapshots().makeAsyncIterator()
            while let snapshot = await arrivals.next() {
                if snapshot.settings != nil {
                    break
                }
            }
            push.send(.refresh)
            let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: PushRegistrationMirror.pluginID)

            /// The token's spellings that could reach a file: its hexadecimal either case, its raw
            /// bytes and their base64.
            func holdsToken(_ data: Data) -> Bool {
                [Data(hexadecimal.utf8), Data(hexadecimal.uppercased().utf8), token, Data(token.base64EncodedString().utf8)]
                    .contains { data.range(of: $0) != nil }
            }
            /// What a store document's payload holds, which the store base64-encodes inside it.
            func payload(of file: URL) -> Data? {
                (try? Data(contentsOf: file)).flatMap(StoreDocument.decoded(from:))?.message.payload
            }
            /// Every regular file under `directory` written since the test started, outside the
            /// store.
            func filesWritten(under directory: URL) -> [URL] {
                let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
                guard let walk = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return [] }
                return walk.compactMap { $0 as? URL }.filter { file in
                    guard !file.standardizedFileURL.path.hasPrefix(store.standardizedFileURL.path),
                          let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true
                    else { return false }
                    return (values.contentModificationDate ?? .distantPast) >= started.addingTimeInterval(-1)
                }
            }
            let duringSession = payload(of: snapshotFile)
            // The test runners give the process a home folder of its own in a temporary folder
            // (CFFIXED_USER_HOME), so all of it is searched: the defaults' plists, Application
            // Support, Caches; run without one, only the defaults' plists are. Beside it, everything
            // under this test's own folder but the store. The system's temporary directory isn't
            // walked: every process on the Mac writes there, and walking it takes seconds.
            let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] != nil
                ? URL.homeDirectory : URL.homeDirectory.appending(path: "Library/Preferences")
            let written = filesWritten(under: home) + filesWritten(under: root)
            let leaks = written.filter { file in
                (try? Data(contentsOf: file)).map(holdsToken) == true || payload(of: file).map(holdsToken) == true
            }
            let defaults = try PropertyListSerialization.data(
                fromPropertyList: UserDefaults.standard.dictionaryRepresentation(), format: .binary, options: 0
            )
            let audit = try JSONEncoder().encode(sessions.auditLog)
            #if os(macOS)
                let logStore = try OSLogStore(scope: .currentProcessIdentifier)
                let logLines = try logStore.getEntries(at: logStore.position(date: started)).compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
                #expect(!logLines.contains { $0.localizedCaseInsensitiveContains(hexadecimal) })
            #endif
            sessionControl.send(.end)
            for await state in sessionControl.snapshots() where !state.isActive {
                break
            }
            let afterSession = payload(of: snapshotFile)

            #expect(duringSession.map(holdsToken) == true)
            #expect(leaks.isEmpty, "Written with the token: \(leaks.map(\.path))")
            #expect(!holdsToken(defaults))
            #expect(!audit.isEmpty)
            #expect(!holdsToken(audit))
            #expect(afterSession == nil)
        }

        @Test("Turning the receiver's gate off removes the capability's snapshot file, token and all")
        func gateRemovesFile() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "PushRegistrationSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let mirror = PushRegistrationMirror(
                sessions: sessions, environment: nil, settings: { NotificationSettings(authorization: .authorized, items: []) }
            )
            mirror.didRegisterForRemoteNotifications(withDeviceToken: Data([0xBE, 0xEF]))
            receiver.enable(.pushRegistration(mirror))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            sessionControl.send(.open(duration: 60))
            let push = try await sidecar.connect(
                toPlugin: PushRegistrationMirror.pluginID,
                snapshot: PushRegistrationMirror.Snapshot.self,
                command: PushRegistrationMirror.Command.self
            )
            var arrivals = push.snapshots().makeAsyncIterator()
            while let snapshot = await arrivals.next() {
                if snapshot.registration != nil {
                    break
                }
            }
            let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: PushRegistrationMirror.pluginID)
            let existedDuring = FileManager.default.fileExists(atPath: snapshotFile.path)

            receiver.isAllowed = { false }

            #expect(existedDuring)
            #expect(!FileManager.default.fileExists(atPath: snapshotFile.path))
        }

        @Test("A snapshot file a launch killed during a session left, token and all, is removed as the next launch's receiver starts")
        func killedLaunchRewritten() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "PushRegistrationSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let firstSessions = DebugDrawerSessions(maximumDuration: 300)
            let firstLaunch = DebugDrawerReceiver(directory: store, sessions: firstSessions)
            let firstMirror = PushRegistrationMirror(
                sessions: firstSessions, environment: nil, settings: { NotificationSettings(authorization: .authorized, items: []) }
            )
            firstMirror.didRegisterForRemoteNotifications(withDeviceToken: Data([0xFE, 0xED]))
            firstLaunch.enable(.pushRegistration(firstMirror))
            try firstLaunch.start()
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            sessionControl.send(.open(duration: 60))
            let push = try await sidecar.connect(
                toPlugin: PushRegistrationMirror.pluginID,
                snapshot: PushRegistrationMirror.Snapshot.self,
                command: PushRegistrationMirror.Command.self
            )
            var arrivals = push.snapshots().makeAsyncIterator()
            while let snapshot = await arrivals.next() {
                if snapshot.registration != nil {
                    break
                }
            }
            let snapshotFile = AppGroupStoreLayout(directory: firstLaunch.appDirectory).snapshotFile(for: PushRegistrationMirror.pluginID)
            // A kill leaves the snapshot file as it was, where stopping would remove it.
            let leftData = try Data(contentsOf: snapshotFile)
            firstLaunch.stop()
            try AppGroupStoreLayout(directory: firstLaunch.appDirectory).write(leftData, to: snapshotFile)
            let left = StoreDocument.decoded(from: leftData)?.message.payload

            let secondSessions = DebugDrawerSessions(maximumDuration: 300)
            let secondLaunch = DebugDrawerReceiver(directory: store, sessions: secondSessions)
            let secondMirror = PushRegistrationMirror(
                sessions: secondSessions, environment: nil, settings: { NotificationSettings(authorization: .authorized, items: []) }
            )
            secondLaunch.enable(.pushRegistration(secondMirror))
            try secondLaunch.start()
            defer { secondLaunch.stop() }

            let leftSnapshot = left.flatMap { try? JSONDecoder().decode(PushRegistrationMirror.Snapshot.self, from: $0) }
            #expect(leftSnapshot?.registration == .registered(deviceToken: "feed"))
            #expect(!FileManager.default.fileExists(atPath: snapshotFile.path))
        }

        @Test("Refresh from the sidecar is refused outside a session and reads the settings again inside one")
        func refreshOnlyInSession() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "PushRegistrationSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let center = SidecarScriptedSettings()
            let mirror = PushRegistrationMirror(sessions: sessions, environment: nil, settings: center.read)
            receiver.enable(.pushRegistration(mirror))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            // Outside a session the capability isn't served, so a sidecar can't connect to it: the
            // refresh is left in the store as its transport would leave it.
            let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
            let refresh = try StoreDocument(TransportMessage(
                kind: .command, pluginID: PushRegistrationMirror.pluginID, payload: TransportMessage.payload(PushRegistrationMirror.Command.refresh)
            )).encoded()
            let (auditEntries, auditEntry) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { auditEntry.yield($0) }
            defer { subscription.cancel() }
            var audit = auditEntries.makeAsyncIterator()

            try layout.write(refresh, to: layout.commands.appending(path: "refresh.json"))
            let refusal = await audit.next()
            sessionControl.send(.open(duration: 60))
            let push = try await sidecar.connect(
                toPlugin: PushRegistrationMirror.pluginID,
                snapshot: PushRegistrationMirror.Snapshot.self,
                command: PushRegistrationMirror.Command.self
            )
            var arrivals = push.snapshots().makeAsyncIterator()
            while let snapshot = await arrivals.next() {
                if snapshot.settings?.authorization == .notDetermined {
                    break
                }
            }
            center.authorization = .authorized
            push.send(.refresh)
            var refreshed: PushRegistrationMirror.Snapshot?
            while let snapshot = await arrivals.next() {
                if snapshot.settings?.authorization == .authorized {
                    refreshed = snapshot
                    break
                }
            }

            #expect(refusal?.capability == PushRegistrationMirror.pluginID)
            #expect(refusal?.event == .commandRefused(.noActiveSession))
            #expect(refreshed?.registration == .notRegistered)
            #expect(center.reads == 2)
        }

        @Test("Not enabled, the capability's commands are refused as unknownCapability and nothing of it is served")
        func notEnabled() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "PushRegistrationSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let suite = temporarySuiteName("PushRegistrationSidecarTests.logLevels")
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            receiver.enable(.logLevels(DebugDrawerLogLevels(adapter: NoSubsystems(), defaults: defaults)))
            try receiver.start()
            defer { receiver.stop() }
            let (auditEntries, auditEntry) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { auditEntry.yield($0) }
            defer { subscription.cancel() }
            var audit = auditEntries.makeAsyncIterator()
            let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
            let command = StoreDocument(
                TransportMessage(
                    kind: .command, pluginID: PushRegistrationMirror.pluginID,
                    payload: try TransportMessage.payload(PushRegistrationMirror.Command.refresh)
                )
            )

            try layout.write(command.encoded(), to: layout.commands.appending(path: "0001.json"))
            let refusal = await audit.next()

            #expect(refusal?.capability == PushRegistrationMirror.pluginID)
            #expect(refusal?.event == .commandRefused(.unknownCapability))
            #expect(!FileManager.default.fileExists(atPath: layout.snapshotFile(for: PushRegistrationMirror.pluginID).path))
        }
    }

    /// Settings the test changes between reads, counting them.
    @MainActor
    private final class SidecarScriptedSettings {
        var authorization = NotificationSettings.Authorization.notDetermined
        private(set) var reads = 0

        func read() async -> NotificationSettings {
            reads += 1
            return NotificationSettings(authorization: authorization, items: [])
        }
    }

    /// A logger adapter listing nothing, so a receiver has some other capability enabled.
    @MainActor
    private struct NoSubsystems: DebugDrawerLogLevelAdapter {
        func elevatableSubsystems() -> [DebugDrawerLogSubsystem] {
            []
        }

        func setLevel(_ level: String, forSubsystem subsystem: String) {}

        func resetLevel(forSubsystem subsystem: String) {}
    }
#endif
