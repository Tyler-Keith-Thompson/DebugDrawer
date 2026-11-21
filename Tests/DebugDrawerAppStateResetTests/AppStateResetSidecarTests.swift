// The app state reset as a sidecar reaches it: a real DebugDrawerReceiver serving the app-group
// store, and the sidecar's DebugDrawerAppGroupStoreTransport (a debug-build type) reading it from
// the same directory, opening sessions through the sessions' own model. The app's state is a
// container in a temporary folder whose Application Support holds the receiver's store too, and a
// real UserDefaults suite; the keychain, cookies and URL cache are fakes.
#if DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerAppStateReset
    @testable import DebugDrawerReceiver
    import Foundation
    import Testing
    #if os(macOS)
        import AppKit
    #endif

    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct AppStateResetSidecarTests {
        @Test(
            """
            Confirmed from the sidecar, the reset waits for the foreground, clears what was listed, keeps the store, the session, \
            the audit log and DebugDrawer's keys, and reports back; no value reaches the store
            """
        )
        func endToEnd() async throws {
            let root = FileManager.default.temporaryDirectory
                .appending(path: "AppStateResetSidecarTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: root) }
            let support = root.appending(path: "Application Support", directoryHint: .isDirectory)
            let store = support.appending(path: "Group Store", directoryHint: .isDirectory)
            for (path, contents) in ["Application Support/orders.sqlite": "orders", "Caches/thumbs/1.png": "png"] {
                let url = root.appending(path: path)
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try Data(contents.utf8).write(to: url)
            }
            let suite = "AppStateResetSidecarTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let secretValue = "value-7f3a9c-never-listed"
            defaults.set(secretValue, forKey: "lastOrder")
            defaults.set(true, forKey: "onboarded")
            defaults.set(["checkout"], forKey: "DebugDrawer.LogLevels.raisedSubsystems")
            let appState = AppState(
                domains: [suite],
                preferences: _PreferenceStore(appDomain: "com.example.unused"),
                keychain: FakeKeychain(),
                container: AppContainer(
                    files: [FileArea(name: "Application Support", directory: support)],
                    caches: [FileArea(name: "Caches", directory: root.appending(path: "Caches"))],
                    kept: [],
                    appFolderName: "com.example.app"
                ),
                cookies: FakeCookieStore(),
                responseCache: FakeResponseCache(),
                cleanup: nil
            )
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let foreground = FakeForeground()
            let model = AppStateResetRequests(
                sessions: sessions, allowing: [.userDefaults, .files, .caches], allowingKeychain: false, appState: appState,
                launchURL: nil, foreground: foreground, now: Date.init
            )
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.enable(.appStateReset(model))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )

            sessionControl.send(.open(duration: 60))
            // Served once the session is open.
            let reset = try await sidecar.connect(
                toPlugin: AppStateResetRequests.pluginID, snapshot: AppStateResetRequests.Snapshot.self, command: AppStateResetRequests.Command.self
            )
            var arrivals = reset.snapshots().makeAsyncIterator()
            while let snapshot = await arrivals.next(), snapshot.sessionID == nil {}
            reset.send(.refresh)
            var listed: AppStateResetRequests.Snapshot?
            while let snapshot = await arrivals.next() {
                if snapshot.listing != nil {
                    listed = snapshot
                    break
                }
            }
            let listing = try #require(listed?.listing)
            reset.send(.reset(listing.categories.map { AppStateResetRequests.Confirmation(category: $0.category, revision: $0.revision) }))
            var waiting: AppStateResetRequests.Snapshot?
            while let snapshot = await arrivals.next() {
                if case .waitingForForeground = snapshot.activity {
                    waiting = snapshot
                    break
                }
            }
            let ordersWhileWaiting = FileManager.default.fileExists(atPath: support.appending(path: "orders.sqlite").path(percentEncoded: false))
            foreground.enter()
            var reported: AppStateResetRequests.Snapshot?
            while let snapshot = await arrivals.next() {
                if snapshot.lastReset != nil {
                    reported = snapshot
                    break
                }
            }
            let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: AppStateResetRequests.pluginID)
            let storeFiles = (FileManager.default.enumerator(at: store, includingPropertiesForKeys: nil)?.allObjects as? [URL]) ?? []
            let stored = storeFiles.compactMap { try? Data(contentsOf: $0) }
            let payloads = storeFiles.compactMap { (try? Data(contentsOf: $0)).flatMap(StoreDocument.decoded(from:))?.message.payload }

            #expect(listing.categories.first { $0.category == .userDefaults }?.items.map(\.text) == ["lastOrder", "onboarded"])
            #expect(listing.categories.first { $0.category == .files }?.items.map(\.text) == ["Application Support/orders.sqlite"])
            #expect(waiting != nil)
            #expect(ordersWhileWaiting)
            #expect(reported?.lastReset?.outcome == .applied([
                AppStateResetRequests.CategoryResult(category: .userDefaults, cleared: 2, failures: []),
                AppStateResetRequests.CategoryResult(category: .caches, cleared: 1, failures: []),
                AppStateResetRequests.CategoryResult(category: .files, cleared: 1, failures: [])
            ]))
            #expect(defaults.object(forKey: "lastOrder") == nil)
            #expect(defaults.object(forKey: "onboarded") == nil)
            #expect(defaults.stringArray(forKey: "DebugDrawer.LogLevels.raisedSubsystems") == ["checkout"])
            #expect(!FileManager.default.fileExists(atPath: support.appending(path: "orders.sqlite").path(percentEncoded: false)))
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Caches/thumbs").path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: snapshotFile.path(percentEncoded: false)))
            #expect(FileManager.default.fileExists(atPath: receiver.appDirectory.appending(path: "presence.json").path(percentEncoded: false)))
            #expect(sessions.snapshot.isActive)
            #expect(sessions.auditLog.map(\.event).contains(.commandApplied))
            #expect(sessions.auditLog.first.map { if case .sessionOpened = $0.event { true } else { false } } == true)
            #expect(!(stored + payloads).contains { $0.range(of: Data(secretValue.utf8)) != nil })
        }

        @Test("Nothing is served or done until the host enables it: a reset is refused as unknownCapability")
        func notEnabled() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "AppStateResetSidecarTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let commands: [(String, Data)] = try [
                (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                (AppStateResetRequests.pluginID, TransportMessage.payload(AppStateResetRequests.Command.refresh))
            ]
            for (index, (id, payload)) in commands.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
            sut.enable(.authActions([]))

            try sut.start()
            defer { sut.stop() }

            #expect(sessions.auditLog.last?.capability == AppStateResetRequests.pluginID)
            #expect(sessions.auditLog.last?.event == .commandRefused(.unknownCapability))
            #expect(!FileManager.default.fileExists(atPath: layout.snapshotFile(for: AppStateResetRequests.pluginID).path(percentEncoded: false)))
        }

        @Test("Outside a session a reset is refused noActiveSession, a disallowed category notExposed, a stale one staleConfirmation, all audited")
        func refusalsAudited() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "AppStateResetSidecarTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let resetID = AppStateResetRequests.pluginID
            let commands: [(String, Data)] = try [
                (resetID, TransportMessage.payload(AppStateResetRequests.Command.reset([.init(category: .caches, revision: "r")]))),
                (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                (resetID, TransportMessage.payload(AppStateResetRequests.Command.reset([.init(category: .keychain, revision: "r")]))),
                (resetID, TransportMessage.payload(AppStateResetRequests.Command.reset([.init(category: .caches, revision: "r")])))
            ]
            for (index, (id, payload)) in commands.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let model = AppStateResetRequests(
                sessions: sessions, allowing: .all, allowingKeychain: false, appState: fixture.appState, launchURL: nil,
                foreground: FakeForeground(isInForeground: true), now: Date.init
            )
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
            sut.enable(.appStateReset(model))
            let expected: [DebugDrawerAuditEntry.Event] = [
                .commandRefused(.noActiveSession), .commandRefused(.notExposed), .commandRefused(.staleConfirmation)
            ]

            try sut.start()
            defer { sut.stop() }

            #expect(sessions.auditLog.filter { $0.capability == resetID }.map(\.event) == expected)
            #expect(fixture.exists("Caches/thumbs/1.png"))
            #expect(fixture.keychain.reads == 0)
        }

        @Test("With requiringGrant, a reset in a session without a grant is refused grantMissing")
        func requiringGrant() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "AppStateResetSidecarTests-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: directory) }
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            #expect(layout.create())
            let commands: [(String, Data)] = try [
                (DebugDrawerSessions.pluginID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
                (AppStateResetRequests.pluginID, TransportMessage.payload(AppStateResetRequests.Command.refresh))
            ]
            for (index, (id, payload)) in commands.enumerated() {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
            }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let model = AppStateResetRequests(
                sessions: sessions, allowing: .all, allowingKeychain: false, appState: fixture.appState, launchURL: nil,
                foreground: FakeForeground(), now: Date.init
            )
            let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
            sut.enable(.appStateReset(model).requiringGrant())

            try sut.start()
            defer { sut.stop() }

            #expect(sessions.auditLog.last?.event == .commandRefused(.grantMissing))
            #expect(model.snapshot.activity == .idle)
        }

        #if os(macOS)
            @Test("With the app's real foreground, a reset left in the store waits until the app becomes active")
            func realForeground() async throws {
                let fixture = try ResetFixture()
                defer { fixture.remove() }
                let store = fixture.root.appending(path: "Store")
                let sessions = DebugDrawerSessions(maximumDuration: 300)
                let model = AppStateResetRequests(
                    sessions: sessions, allowing: [.caches], allowingKeychain: false, appState: fixture.appState, launchURL: nil,
                    foreground: _AppForeground(), now: Date.init
                )
                let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
                receiver.enable(.appStateReset(model))
                try receiver.start()
                defer { receiver.stop() }
                let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
                let sessionControl = try await sidecar.connect(
                    toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
                )
                sessionControl.send(.open(duration: 60))
                // Served once the session is open.
                let reset = try await sidecar.connect(
                    toPlugin: AppStateResetRequests.pluginID,
                    snapshot: AppStateResetRequests.Snapshot.self,
                    command: AppStateResetRequests.Command.self
                )
                reset.send(.refresh)
                for await snapshot in model.$snapshot.values where snapshot.listing != nil {
                    break
                }
                let revision = try #require(model.snapshot.listing?.categories.first?.revision)

                reset.send(.reset([AppStateResetRequests.Confirmation(category: .caches, revision: revision)]))
                for await snapshot in model.$snapshot.values {
                    if case .waitingForForeground = snapshot.activity {
                        break
                    }
                }
                let cachesWhileInactive = fixture.exists("Caches/thumbs/1.png")
                NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
                for await snapshot in model.$snapshot.values where snapshot.lastReset != nil {
                    break
                }

                #expect(cachesWhileInactive)
                #expect(!fixture.exists("Caches/thumbs/1.png"))
                #expect(fixture.exists("Caches/DebugDrawer/Recordings/a.mov"))
            }
        #endif
    }
#endif
