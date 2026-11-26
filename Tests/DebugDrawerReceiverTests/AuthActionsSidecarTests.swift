// The auth actions as a sidecar reaches them: a real DebugDrawerReceiver serving the app-group
// store, and the sidecar's DebugDrawerAppGroupStoreTransport (a debug-build type) reading it from
// the same directory, opening its session through the sessions' own model. The host's handlers
// hold recognisable fake tokens, and everything the run leaves behind is searched for them.
#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerReceiver
    import Foundation
    #if os(macOS)
        import OSLog
    #endif
    import Testing

    /// The app's sign-in: an access token its handlers expire, replace and drop, standing in for a
    /// host's auth service. The tokens are fixed so the test can search for them.
    @MainActor
    private final class FakeSignIn {
        enum State: Equatable {
            case signedIn
            case expired
            case signedOut
        }

        static let firstToken = Data([
            0x7B, 0x1D, 0xE4, 0x09, 0xA2, 0x5C, 0x33, 0xF8, 0x6E, 0x91, 0x0B, 0xD7, 0x48, 0xC5, 0x2A, 0x96,
            0x1F, 0x83, 0xEA, 0x50, 0x3D, 0xB4, 0x67, 0x0C
        ])
        static let refreshedToken = Data([
            0xC9, 0x02, 0x5F, 0xA8, 0x14, 0xE7, 0x6B, 0x3E, 0xD0, 0x85, 0x29, 0xF1, 0x4C, 0x9A, 0x07, 0xB6,
            0x58, 0xE3, 0x12, 0xAF, 0x70, 0x2D, 0xCB, 0x94
        ])

        private(set) var state = State.signedIn
        private(set) var accessToken: Data? = FakeSignIn.firstToken

        var actions: [DebugDrawerAuthAction] {
            [
                .expireAccessToken { [unowned self] in
                    guard accessToken != nil else { return .failed("Not signed in") }
                    state = .expired
                    return .succeeded
                },
                .forceRefresh { [unowned self] in
                    guard accessToken != nil else { return .failed("Not signed in") }
                    accessToken = Self.refreshedToken
                    state = .signedIn
                    return .succeeded
                },
                .logOut { [unowned self] in
                    accessToken = nil
                    state = .signedOut
                    return .succeeded
                }
            ]
        }
    }

    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct AuthActionsSidecarTests {
        @Test("Every action runs from the sidecar through the store, and no token reaches the store, the audit log, defaults or logs")
        func noCredentialCrossesTheTransport() async throws {
            let started = Date()
            let root = FileManager.default.temporaryDirectory.appending(path: "AuthActionsSidecarTests-\(UUID().uuidString)")
            let store = root.appending(path: "Group/DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            let signIn = FakeSignIn()
            try receiver.enable(.authActions(signIn.actions, launchURL: URL(string: "shop-internal://")))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: store))
            let sessionControl = try await sidecar.connect(
                toPlugin: DebugDrawerSessions.pluginID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let sessionStates = sessionControl.snapshots()
            sessionControl.send(.open(duration: 60))
            for await state in sessionStates where state.isActive {
                break
            }
            // Served only within the session.
            let actions = try await sidecar.connect(
                toPlugin: DebugDrawerAuthActions.pluginID,
                snapshot: DebugDrawerAuthActions.Snapshot.self,
                command: DebugDrawerAuthActions.Command.self
            )
            var arrivals = actions.snapshots().makeAsyncIterator()
            var received: [DebugDrawerAuthActions.Snapshot] = []
            var sent: [DebugDrawerAuthActions.Command] = []
            // Each request, then the snapshot holding its outcome: expire, refresh, log out, and a
            // refresh once signed out, which fails.
            let requests = ["expire-access-token", "force-refresh", "log-out", "force-refresh"]
            var outcomes: [DebugDrawerAuthActions.Status] = []
            for (index, id) in requests.enumerated() {
                let command = DebugDrawerAuthActions.Command.perform(action: id)
                actions.send(command)
                sent.append(command)
                while let snapshot = await arrivals.next() {
                    received.append(snapshot)
                    if let run = snapshot.actions.first(where: { $0.id == id })?.lastRun, run.number == index + 1, run.status != .running {
                        outcomes.append(run.status)
                        break
                    }
                }
            }
            let snapshotFile = AppGroupStoreLayout(directory: receiver.appDirectory).snapshotFile(for: DebugDrawerAuthActions.pluginID)

            let tokens = [FakeSignIn.firstToken, FakeSignIn.refreshedToken]
            /// The tokens' spellings that could reach a file: raw bytes, hexadecimal either case,
            /// base64 and base64url.
            func holdsToken(_ data: Data) -> Bool {
                tokens.flatMap { token in
                    let hexadecimal = token.map { String(format: "%02x", $0) }.joined()
                    let base64 = token.base64EncodedString()
                    let base64URL = base64.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                        .trimmingCharacters(in: CharacterSet(charactersIn: "="))
                    return [token, Data(hexadecimal.utf8), Data(hexadecimal.uppercased().utf8), Data(base64.utf8), Data(base64URL.utf8)]
                }
                .contains { data.range(of: $0) != nil }
            }
            /// What a store document's payload holds, which the store base64-encodes inside it.
            func payload(of file: URL) -> Data? {
                (try? Data(contentsOf: file)).flatMap(StoreDocument.decoded(from:))?.message.payload
            }
            /// Every regular file under `directory`, and only those written since the test
            /// started when `recentOnly`.
            func files(under directory: URL, recentOnly: Bool) -> [URL] {
                let keys: [URLResourceKey] = [.isRegularFileKey, .contentModificationDateKey]
                guard let walk = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return [] }
                return walk.compactMap { $0 as? URL }.filter { file in
                    guard let values = try? file.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { return false }
                    return !recentOnly || (values.contentModificationDate ?? .distantPast) >= started.addingTimeInterval(-1)
                }
            }
            // The whole of this test's folder: the store's snapshots (the sessions' and the
            // actions'), its presence file, and any command left. Beside it the test runner's own
            // home folder (CFFIXED_USER_HOME), where defaults and Application Support go; run
            // without one, only the defaults' plists. The system's temporary directory isn't
            // walked: every process on the Mac writes there.
            let storeFiles = files(under: root, recentOnly: false)
            let home = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] != nil
                ? URL.homeDirectory : URL.homeDirectory.appending(path: "Library/Preferences")
            let written = storeFiles + files(under: home, recentOnly: true)
            let leaks = written.filter { file in
                (try? Data(contentsOf: file)).map(holdsToken) == true || payload(of: file).map(holdsToken) == true
            }
            let snapshotsReceived = try received.map { try JSONEncoder().encode($0) }
            // The search's own check: a store document holding the token as a Data field (base64
            // in JSON, base64 again in the store) is found, so a clean result means something.
            let canary = FileManager.default.temporaryDirectory.appending(path: "AuthActionsSidecarCanary-\(UUID().uuidString).json")
            let canaryPayload = try JSONEncoder().encode(["token": FakeSignIn.refreshedToken])
            try StoreDocument(TransportMessage(kind: .snapshot, pluginID: DebugDrawerAuthActions.pluginID, payload: canaryPayload)).encoded()
                .write(to: canary)
            defer { try? FileManager.default.removeItem(at: canary) }
            let commandsSent = try sent.map { try JSONEncoder().encode($0) }
            let audit = try JSONEncoder().encode(sessions.auditLog)
            let defaults = try PropertyListSerialization.data(
                fromPropertyList: UserDefaults.standard.dictionaryRepresentation(), format: .binary, options: 0
            )
            #if os(macOS)
                let logStore = try OSLogStore(scope: .currentProcessIdentifier)
                let logLines = try logStore.getEntries(at: logStore.position(date: started)).compactMap { ($0 as? OSLogEntryLog)?.composedMessage }
                #expect(!logLines.contains { holdsToken(Data($0.utf8)) || holdsToken(Data($0.lowercased().utf8)) })
            #endif

            let expectedOutcomes: [DebugDrawerAuthActions.Status] = [.succeeded, .succeeded, .succeeded, .failed(message: "Not signed in")]
            let expectedAudit = Array(repeating: DebugDrawerAuditEntry.Event.commandApplied, count: requests.count)
            #expect(outcomes == expectedOutcomes)
            #expect(signIn.state == .signedOut)
            #expect(sessions.auditLog.filter { $0.capability == DebugDrawerAuthActions.pluginID }.map(\.event) == expectedAudit)
            #expect(storeFiles.map { $0.resolvingSymlinksInPath().path }.contains(snapshotFile.resolvingSymlinksInPath().path))
            #expect(!received.isEmpty)
            #expect(payload(of: canary).map(holdsToken) == true)
            #expect(leaks.isEmpty, "Written with a token: \(leaks.map(\.path))")
            #expect(!snapshotsReceived.contains(where: holdsToken))
            #expect(!commandsSent.contains(where: holdsToken))
            #expect(!holdsToken(audit))
            #expect(!holdsToken(defaults))
        }
    }
#endif
