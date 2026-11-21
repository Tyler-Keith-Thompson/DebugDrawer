// Grants as a sidecar meets them: a real DebugDrawerReceiver serving the app-group store, and the
// sidecar's DebugDrawerAppGroupStoreTransport (a debug-build type) on the same directory, opening
// sessions through the sessions' own model with grants the README's test signer issued. The
// sessions run on a clock the test moves and a timer it fires, so validity windows and expiry are
// exact. Each test waits for the audit entries its commands produce, which the sessions publish
// as the receiver performs each command file.
#if DEBUG
    import CryptoKit
    import DebugDrawer
    @testable import DebugDrawerReceiver
    import Foundation
    import os
    import Testing

    /// A wall clock the test moves by hand.
    private final class MovableClock: SessionClock, Sendable {
        private let time: OSAllocatedUnfairLock<Date>

        init(_ start: Date) {
            time = OSAllocatedUnfairLock(initialState: start)
        }

        var now: Date {
            time.withLock { $0 }
        }

        func set(_ date: Date) {
            time.withLock { $0 = date }
        }
    }

    /// A session timer that fires when the test says.
    @MainActor
    private final class ManualTimer: SessionTimer {
        private(set) var scheduled: Date?
        private var fire: (@MainActor () -> Void)?

        func schedule(at date: Date, _ fire: @escaping @MainActor () -> Void) {
            scheduled = date
            self.fire = fire
        }

        func cancel() {
            scheduled = nil
            fire = nil
        }
    }

    /// A capability of the host's own: a log level a sidecar elevates.
    @MainActor
    private final class LogLevelModel: DebugDrawerPluginModel {
        struct Snapshot: Codable, Equatable, Sendable {
            var level = "info"
        }

        enum Command: Codable, Equatable, Sendable {
            case set(String)
            case reset
        }

        @Published private(set) var snapshot = Snapshot()

        func perform(_ command: Command) {
            switch command {
            case let .set(level): snapshot.level = level
            case .reset: snapshot.level = "info"
            }
        }
    }

    /// How a grant presented at open is wrong, and the refusal the audit log must give for it.
    enum BadGrant: String, CaseIterable, CustomTestStringConvertible, Sendable {
        case none, badSignature, wrongAudience, tamperedPayload, expired, notYetValid, malformed

        var testDescription: String {
            rawValue
        }

        var expectedRefusal: DebugDrawerAuditEntry.Refusal {
            switch self {
            case .none: .grantMissing
            case .badSignature, .tamperedPayload, .malformed: .grantInvalid
            case .wrongAudience: .grantWrongAudience
            case .expired: .grantExpired
            case .notYetValid: .grantNotYetValid
            }
        }
    }

    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct GrantSessionTests {
        private static let start = Date(timeIntervalSince1970: 1_778_307_200)
        private let flagsID = DebugDrawerFeatureFlagOverrides.pluginID
        private let sessionsID = DebugDrawerSessions.pluginID

        @Test(
            "With a verifier, opening with a bad grant is refused with its reason, and the command after it as noActiveSession",
            arguments: BadGrant.allCases
        )
        func badGrantRefused(_ badGrant: BadGrant) async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "GrantSessionTests-\(UUID().uuidString)")
            let serverKey = Curve25519.Signing.PrivateKey()
            let signer = DebugDrawerTestGrantSigner(key: serverKey)
            let clock = MovableClock(Self.start)
            let policy = DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: "com.example.MyApp"
            )
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: ManualTimer())
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            let flags = FlagServiceAdapter()
            let flagSuite = "GrantSessionTests.flags.\(UUID().uuidString)"
            let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
            defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
            receiver.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: flags, defaults: flagDefaults)))
            try receiver.start()
            defer { receiver.stop() }
            let valid = try signer.token(for: DebugDrawerGrant(
                id: "g-1", subject: "jane@example.com", audiences: ["com.example.MyApp"],
                capabilities: [flagsID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            ))
            let token: String? = switch badGrant {
            case .none:
                nil
            case .badSignature:
                try DebugDrawerTestGrantSigner(key: Curve25519.Signing.PrivateKey()).token(for: DebugDrawerGrant(
                    id: "g-1", subject: "jane@example.com", audiences: ["com.example.MyApp"],
                    capabilities: [flagsID],
                    notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
                ))
            case .wrongAudience:
                try signer.token(for: DebugDrawerGrant(
                    id: "g-1", subject: "jane@example.com", audiences: ["com.example.OtherApp"],
                    capabilities: [flagsID],
                    notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
                ))
            case .tamperedPayload:
                // Another grant's claims, longer-lived, under the valid grant's signature.
                try {
                    let longer = try signer.token(for: DebugDrawerGrant(
                        id: "g-1", subject: "jane@example.com", audiences: ["com.example.MyApp"],
                        capabilities: [flagsID],
                        notBefore: Self.start, expires: Self.start.addingTimeInterval(86400)
                    )).split(separator: ".")
                    let original = valid.split(separator: ".")
                    return "\(longer[0]).\(longer[1]).\(original[2])"
                }()
            case .expired:
                try signer.token(for: DebugDrawerGrant(
                    id: "g-1", subject: "jane@example.com", audiences: ["com.example.MyApp"],
                    capabilities: [flagsID],
                    notBefore: Self.start.addingTimeInterval(-600), expires: Self.start
                ))
            case .notYetValid:
                try signer.token(for: DebugDrawerGrant(
                    id: "g-1", subject: "jane@example.com", audiences: ["com.example.MyApp"],
                    capabilities: [flagsID],
                    notBefore: Self.start.addingTimeInterval(61), expires: Self.start.addingTimeInterval(600)
                ))
            case .malformed:
                "\(valid).extra"
            }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sessionControl = try await sidecar.connect(
                toPlugin: sessionsID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            // No session opens, so the flags aren't served and a sidecar can't connect to them:
            // the command is left in the store as its transport would leave it.
            let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
            let flagCommand = try StoreDocument(TransportMessage(
                kind: .command, pluginID: flagsID,
                payload: TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "new-checkout", value: .bool(true)))
            )).encoded()
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            var recorded = arrivals.makeAsyncIterator()
            let expected = [
                DebugDrawerAuditEntry(date: Self.start, sessionID: nil, capability: sessionsID, event: .commandRefused(badGrant.expectedRefusal)),
                DebugDrawerAuditEntry(date: Self.start, sessionID: nil, capability: flagsID, event: .commandRefused(.noActiveSession))
            ]

            sessionControl.send(.open(duration: 300, grant: token))
            let first = await recorded.next()
            try layout.write(flagCommand, to: layout.commands.appending(path: "flag.json"))
            let second = await recorded.next()

            #expect([first, second] == expected)
            #expect(sessions.snapshot == .inactive)
            #expect(flags.overrides.isEmpty)
            let auditJSON = try #require(String(bytes: JSONEncoder().encode(sessions.auditLog), encoding: .utf8))
            if let signature = token?.split(separator: ".").last, signature.count > 8 {
                #expect(!auditJSON.contains(signature))
            }
        }

        @Test(
            "A valid grant opens a session no longer than itself, its capability is applied, and the audit names it, never its token"
        )
        func validGrantApplied() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "GrantSessionTests-\(UUID().uuidString)")
            let serverKey = Curve25519.Signing.PrivateKey()
            let clock = MovableClock(Self.start)
            let timer = ManualTimer()
            let policy = DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: "com.example.MyApp"
            )
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: timer)
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            let flags = FlagServiceAdapter()
            let flagSuite = "GrantSessionTests.flags.\(UUID().uuidString)"
            let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
            defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
            receiver.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: flags, defaults: flagDefaults)))
            try receiver.start()
            defer { receiver.stop() }
            let token = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "g-valid", subject: "jane@example.com", audiences: ["com.example.MyApp"],
                capabilities: [flagsID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            ))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sessionControl = try await sidecar.connect(
                toPlugin: sessionsID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            var recorded = arrivals.makeAsyncIterator()
            var states = sessionControl.snapshots().makeAsyncIterator()
            let expectedGrant = DebugDrawerGrant(
                id: "g-valid", subject: "jane@example.com", audiences: ["com.example.MyApp"], capabilities: [flagsID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            )
            let expectedExpiry = Self.start.addingTimeInterval(300)
            let expectedOverrides: [String: DebugDrawerFeatureFlagValue] = ["new-checkout": .bool(true)]

            sessionControl.send(.open(duration: 900, grant: token))
            let opened = await recorded.next()
            // Served once the session is open.
            let flagControl = try await sidecar.connect(
                toPlugin: flagsID, snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self, command: DebugDrawerFeatureFlagOverrides.Command.self
            )
            flagControl.send(.setOverride(key: "new-checkout", value: .bool(true)))
            let applied = await recorded.next()
            var seen: DebugDrawerSessionState?
            while let state = await states.next() {
                seen = state
                if state.isActive { break }
            }

            let session = try #require(sessions.snapshot.session)
            #expect(opened == DebugDrawerAuditEntry(
                date: Self.start, sessionID: session.id, capability: sessionsID,
                event: .sessionOpened(expires: expectedExpiry, grant: .init(id: "g-valid", subject: "jane@example.com"))
            ))
            #expect(applied == DebugDrawerAuditEntry(date: Self.start, sessionID: session.id, capability: flagsID, event: .commandApplied))
            #expect(session.expires == expectedExpiry)
            #expect(timer.scheduled == expectedExpiry)
            #expect(session.grant == expectedGrant)
            #expect(seen?.session?.grant == expectedGrant)
            #expect(flags.overrides == expectedOverrides)
            let auditJSON = try #require(String(bytes: JSONEncoder().encode(sessions.auditLog), encoding: .utf8))
            let signature = try #require(token.split(separator: ".").last)
            #expect(!auditJSON.contains(signature))
            #expect(!auditJSON.contains(token))
            let stored = try FileManager.default.subpathsOfDirectory(atPath: directory.path).compactMap { path -> String? in
                let url = directory.appending(path: path)
                guard let data = try? Data(contentsOf: url) else { return nil }
                return String(bytes: data, encoding: .utf8)
            }
            #expect(!stored.contains { $0.contains(signature) })
        }

        @Test("A grant issued up to the clock-skew tolerance ahead of the device's clock opens a session")
        func clockSkewTolerated() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "GrantSessionTests-\(UUID().uuidString)")
            let serverKey = Curve25519.Signing.PrivateKey()
            let clock = MovableClock(Self.start)
            let policy = DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: "com.example.MyApp",
                clockSkewTolerance: 60
            )
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: ManualTimer())
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            let flagSuite = "GrantSessionTests.flags.\(UUID().uuidString)"
            let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
            defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
            receiver.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: FlagServiceAdapter(), defaults: flagDefaults)))
            try receiver.start()
            defer { receiver.stop() }
            let token = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "g-skew", subject: "jane@example.com", audiences: ["com.example.MyApp"],
                capabilities: [flagsID],
                notBefore: Self.start.addingTimeInterval(60), expires: Self.start.addingTimeInterval(300)
            ))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sessionControl = try await sidecar.connect(
                toPlugin: sessionsID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            var recorded = arrivals.makeAsyncIterator()

            sessionControl.send(.open(duration: 600, grant: token))
            let opened = await recorded.next()

            #expect(opened?.event == .sessionOpened(
                expires: Self.start.addingTimeInterval(300), grant: .init(id: "g-skew", subject: "jane@example.com")
            ))
        }

        @Test("A grant valid for one capability refuses a command to another as capabilityNotGranted, while its own is applied")
        func outOfScopeRefused() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "GrantSessionTests-\(UUID().uuidString)")
            let serverKey = Curve25519.Signing.PrivateKey()
            let clock = MovableClock(Self.start)
            let policy = DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: "com.example.MyApp"
            )
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: ManualTimer())
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            let flags = FlagServiceAdapter()
            let logLevels = LogLevelModel()
            let flagSuite = "GrantSessionTests.flags.\(UUID().uuidString)"
            let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
            defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
            receiver.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: flags, defaults: flagDefaults)))
            receiver.enable(.model(logLevels, id: "MyApp.LogLevels", scope: .session(revertWith: .reset)))
            try receiver.start()
            defer { receiver.stop() }
            let token = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "g-flags", subject: "jane@example.com", audiences: ["com.example.MyApp"],
                capabilities: [flagsID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            ))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sessionControl = try await sidecar.connect(
                toPlugin: sessionsID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            // The grant doesn't list the log levels, so they aren't served and a sidecar can't
            // connect to them: the command is left in the store as its transport would leave it.
            let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
            let logCommand = try StoreDocument(TransportMessage(
                kind: .command, pluginID: "MyApp.LogLevels", payload: TransportMessage.payload(LogLevelModel.Command.set("debug"))
            )).encoded()
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            var recorded = arrivals.makeAsyncIterator()
            let expectedOverrides: [String: DebugDrawerFeatureFlagValue] = ["new-checkout": .bool(true)]

            sessionControl.send(.open(duration: 300, grant: token))
            _ = await recorded.next()
            try layout.write(logCommand, to: layout.commands.appending(path: "log.json"))
            let refused = await recorded.next()
            // Served once the session, whose grant lists them, is open.
            let flagControl = try await sidecar.connect(
                toPlugin: flagsID, snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self, command: DebugDrawerFeatureFlagOverrides.Command.self
            )
            flagControl.send(.setOverride(key: "new-checkout", value: .bool(true)))
            let applied = await recorded.next()

            let session = try #require(sessions.snapshot.session)
            #expect(refused == DebugDrawerAuditEntry(
                date: Self.start, sessionID: session.id, capability: "MyApp.LogLevels", event: .commandRefused(.capabilityNotGranted)
            ))
            #expect(applied?.event == .commandApplied)
            #expect(logLevels.snapshot == LogLevelModel.Snapshot())
            #expect(flags.overrides == expectedOverrides)
        }

        @Test("A command after the grant's expiry, before the timer fires, expires the session first and is refused")
        func grantExpiresMidSession() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "GrantSessionTests-\(UUID().uuidString)")
            let serverKey = Curve25519.Signing.PrivateKey()
            let clock = MovableClock(Self.start)
            let policy = DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: "com.example.MyApp"
            )
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: ManualTimer())
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            let flags = FlagServiceAdapter()
            let flagSuite = "GrantSessionTests.flags.\(UUID().uuidString)"
            let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
            defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
            receiver.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: flags, defaults: flagDefaults)))
            try receiver.start()
            defer { receiver.stop() }
            let token = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "g-short", subject: "jane@example.com", audiences: ["com.example.MyApp"],
                capabilities: [flagsID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(120)
            ))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sessionControl = try await sidecar.connect(
                toPlugin: sessionsID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            var recorded = arrivals.makeAsyncIterator()
            let expiry = Self.start.addingTimeInterval(120)

            sessionControl.send(.open(duration: 600, grant: token))
            let opened = await recorded.next()
            // Served once the session is open.
            let flagControl = try await sidecar.connect(
                toPlugin: flagsID, snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self, command: DebugDrawerFeatureFlagOverrides.Command.self
            )
            clock.set(expiry)
            flagControl.send(.setOverride(key: "new-checkout", value: .bool(true)))
            let ended = await recorded.next()
            let refused = await recorded.next()

            let sessionID = try #require(opened?.sessionID)
            #expect(opened?.event == .sessionOpened(expires: expiry, grant: .init(id: "g-short", subject: "jane@example.com")))
            #expect(ended == DebugDrawerAuditEntry(date: expiry, sessionID: sessionID, capability: sessionsID, event: .sessionEnded(.expired)))
            #expect(refused == DebugDrawerAuditEntry(date: expiry, sessionID: nil, capability: flagsID, event: .commandRefused(.noActiveSession)))
            #expect(flags.overrides.isEmpty)
        }

        @Test("A grant opens one session: presented again after that session ends, it is refused as grantReplayed")
        func replayRefused() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "GrantSessionTests-\(UUID().uuidString)")
            let serverKey = Curve25519.Signing.PrivateKey()
            let clock = MovableClock(Self.start)
            let policy = DebugDrawerGrantPolicy(
                verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: "com.example.MyApp"
            )
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: ManualTimer())
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            let flagSuite = "GrantSessionTests.flags.\(UUID().uuidString)"
            let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
            defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
            receiver.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: FlagServiceAdapter(), defaults: flagDefaults)))
            try receiver.start()
            defer { receiver.stop() }
            let signer = DebugDrawerTestGrantSigner(key: serverKey)
            let token = try signer.token(for: DebugDrawerGrant(
                id: "g-once", subject: "jane@example.com", audiences: ["com.example.MyApp"],
                capabilities: [flagsID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            ))
            let fresh = try signer.token(for: DebugDrawerGrant(
                id: "g-twice", subject: "jane@example.com", audiences: ["com.example.MyApp"],
                capabilities: [flagsID],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            ))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sessionControl = try await sidecar.connect(
                toPlugin: sessionsID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            var recorded = arrivals.makeAsyncIterator()

            sessionControl.send(.open(duration: 60, grant: token))
            _ = await recorded.next()
            sessionControl.send(.end)
            _ = await recorded.next()
            sessionControl.send(.open(duration: 60, grant: token))
            let replayed = await recorded.next()
            sessionControl.send(.open(duration: 60, grant: fresh))
            let reopened = await recorded.next()

            #expect(replayed == DebugDrawerAuditEntry(
                date: Self.start, sessionID: nil, capability: sessionsID, event: .commandRefused(.grantReplayed)
            ))
            #expect(reopened?.event == .sessionOpened(
                expires: Self.start.addingTimeInterval(60), grant: .init(id: "g-twice", subject: "jane@example.com")
            ))
        }

        @Test("With no verifier, a session opens as before, a token sent with it is ignored, and commands are applied")
        func noVerifier() async throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: "GrantSessionTests-\(UUID().uuidString)")
            let clock = MovableClock(Self.start)
            let sessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
            let flags = FlagServiceAdapter()
            let flagSuite = "GrantSessionTests.flags.\(UUID().uuidString)"
            let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
            defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
            receiver.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: flags, defaults: flagDefaults)))
            try receiver.start()
            defer { receiver.stop() }
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
            let sessionControl = try await sidecar.connect(
                toPlugin: sessionsID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let subscription = sessions.auditEntries.sink { arrival.yield($0) }
            defer { subscription.cancel() }
            var recorded = arrivals.makeAsyncIterator()

            sessionControl.send(.open(duration: 60))
            let opened = await recorded.next()
            // Served once the session is open.
            let flagControl = try await sidecar.connect(
                toPlugin: flagsID, snapshot: DebugDrawerFeatureFlagOverrides.Snapshot.self, command: DebugDrawerFeatureFlagOverrides.Command.self
            )
            flagControl.send(.setOverride(key: "new-checkout", value: .bool(true)))
            let applied = await recorded.next()
            sessionControl.send(.end)
            _ = await recorded.next()
            _ = await recorded.next()
            sessionControl.send(.open(duration: 60, grant: "not-a-grant"))
            let openedWithToken = await recorded.next()

            #expect(sessions.grantPolicy == nil)
            #expect(opened?.event == .sessionOpened(expires: Self.start.addingTimeInterval(60)))
            #expect(applied?.event == .commandApplied)
            #expect(flags.overrides.isEmpty)
            #expect(openedWithToken?.event == .sessionOpened(expires: Self.start.addingTimeInterval(60)))
            #expect(sessions.snapshot.session?.grant == nil)
        }

        @Test("A capability that requires a grant is refused as grantMissing without a verifier, and applied with a grant that lists it")
        func requiringGrant() async throws {
            let withoutDirectory = FileManager.default.temporaryDirectory.appending(path: "GrantSessionTests-\(UUID().uuidString)")
            let withDirectory = FileManager.default.temporaryDirectory.appending(path: "GrantSessionTests-\(UUID().uuidString)")
            let serverKey = Curve25519.Signing.PrivateKey()
            let clock = MovableClock(Self.start)
            let plainSessions = DebugDrawerSessions(maximumDuration: 600, auditCapacity: 100, clock: clock, timer: ManualTimer())
            let plainReceiver = DebugDrawerReceiver(directory: withoutDirectory, sessions: plainSessions)
            let plainLevels = LogLevelModel()
            plainReceiver.enable(.model(plainLevels, id: "MyApp.LogLevels", scope: .session(revertWith: .reset)).requiringGrant())
            try plainReceiver.start()
            defer { plainReceiver.stop() }
            let grantedSessions = DebugDrawerSessions(
                maximumDuration: 600, auditCapacity: 100,
                grantPolicy: DebugDrawerGrantPolicy(
                    verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: "com.example.MyApp"
                ),
                clock: clock, timer: ManualTimer()
            )
            let grantedReceiver = DebugDrawerReceiver(directory: withDirectory, sessions: grantedSessions)
            let grantedLevels = LogLevelModel()
            grantedReceiver.enable(.model(grantedLevels, id: "MyApp.LogLevels", scope: .session(revertWith: .reset)).requiringGrant())
            try grantedReceiver.start()
            defer { grantedReceiver.stop() }
            let token = try DebugDrawerTestGrantSigner(key: serverKey).token(for: DebugDrawerGrant(
                id: "g-levels", subject: "jane@example.com", audiences: ["com.example.MyApp"],
                capabilities: ["MyApp.LogLevels"],
                notBefore: Self.start, expires: Self.start.addingTimeInterval(300)
            ))
            let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
            let plainSubscription = plainSessions.auditEntries.sink { arrival.yield($0) }
            defer { plainSubscription.cancel() }
            let grantedSubscription = grantedSessions.auditEntries.sink { arrival.yield($0) }
            defer { grantedSubscription.cancel() }
            var recorded = arrivals.makeAsyncIterator()
            let plainSidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: withoutDirectory))
            let plainControl = try await plainSidecar.connect(
                toPlugin: sessionsID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )
            // Without a grant the log levels aren't served, so a sidecar can't connect to them: the
            // command is left in the store as its transport would leave it.
            let plainLayout = AppGroupStoreLayout(directory: plainReceiver.appDirectory)
            let plainCommand = try StoreDocument(TransportMessage(
                kind: .command, pluginID: "MyApp.LogLevels", payload: TransportMessage.payload(LogLevelModel.Command.set("debug"))
            )).encoded()
            let grantedSidecar = try DebugDrawerAppGroupStoreTransport(directory: AppGroupStoreLayout.appDirectory(inStore: withDirectory))
            let grantedControl = try await grantedSidecar.connect(
                toPlugin: sessionsID, snapshot: DebugDrawerSessionState.self, command: DebugDrawerSessionCommand.self
            )

            plainControl.send(.open(duration: 60))
            _ = await recorded.next()
            try plainLayout.write(plainCommand, to: plainLayout.commands.appending(path: "log.json"))
            let refused = await recorded.next()
            grantedControl.send(.open(duration: 60, grant: token))
            _ = await recorded.next()
            let grantedLog = try await grantedSidecar.connect(
                toPlugin: "MyApp.LogLevels", snapshot: LogLevelModel.Snapshot.self, command: LogLevelModel.Command.self
            )
            grantedLog.send(.set("debug"))
            let applied = await recorded.next()

            #expect(refused?.event == .commandRefused(.grantMissing))
            #expect(refused?.capability == "MyApp.LogLevels")
            #expect(plainLevels.snapshot.level == "info")
            #expect(applied?.event == .commandApplied)
            #expect(grantedLevels.snapshot.level == "debug")
        }
    }
#endif
