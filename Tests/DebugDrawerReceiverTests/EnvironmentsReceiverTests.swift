import CryptoKit
@testable import DebugDrawerReceiver
import DebugDrawerTestSupport
import Foundation
import os
import Testing

/// The host's backend configuration as the receiver switches it: the environment it points at,
/// and every environment it was told to activate, in order. Its base URLs are the host's own and
/// never reach the receiver.
@MainActor
private final class FakeBackend: DebugDrawerEnvironmentAdapter {
    static let baseURLs = [
        "production": "https://api.example.com",
        "staging": "https://staging.api.example.com",
        "canary": "https://canary.api.example.com"
    ]

    private(set) var baseURL = FakeBackend.baseURLs["production"]
    private(set) var activated: [DebugDrawerEnvironment] = []

    func activate(_ environment: DebugDrawerEnvironment) {
        baseURL = Self.baseURLs[environment.id]
        activated.append(environment)
    }
}

/// A flag service with nothing to override, so a receiver serves a capability other than
/// environments.
@MainActor
private final class EmptyFlagAdapter: DebugDrawerFeatureFlagAdapter {
    func overridableFlags() -> [DebugDrawerFeatureFlag] { [] }
    func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {}
    func clearOverride(forKey key: String) {}
}

/// A host gate the test turns on and off, standing in for a remote configuration value.
@MainActor
private final class Gate {
    var isOpen = true
}

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

/// A session timer that fires when the test says, as the system's would at the expiry.
@MainActor
private final class ManualTimer: SessionTimer {
    private(set) var scheduled: Date?
    private var pending: (@MainActor () -> Void)?

    func schedule(at date: Date, _ fire: @escaping @MainActor () -> Void) {
        scheduled = date
        pending = fire
    }

    func cancel() {
        scheduled = nil
        pending = nil
    }

    func fire() {
        let fire = pending
        cancel()
        fire?()
    }
}

// Environment switching end to end through the receiver alone, as a release build links it (no
// drawer): only an environment the host listed can be activated, by ID, and an unknown or
// URL-shaped one is refused; the host's adapter is handed its own value; the default comes back
// as the session ends, expires, a gate turns off, or the next launch follows a kill; nothing is
// served until the host enables it; and under a grant policy a switch needs a grant listing the
// capability. Commands are files left in the store the way a sidecar's transport leaves them; the
// receiver performs those waiting as it starts or re-evaluates its gates. Sessions run on a clock
// the test moves and a timer it fires, so expiry is exact and nothing waits. Each test keeps the
// model's record in a defaults suite of its own.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct EnvironmentsReceiverTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let environmentsID = DebugDrawerEnvironments.pluginID
    private let flagsID = DebugDrawerFeatureFlagOverrides.pluginID
    private let sessionsID = DebugDrawerSessions.pluginID
    private let production = DebugDrawerEnvironment("production", title: "Production")
    private let staging = DebugDrawerEnvironment("staging", title: "Staging", summary: "Yesterday's server build")
    private let canary = DebugDrawerEnvironment("canary", title: "Canary")

    @Test("In a session, a sidecar reads, from the store, the default and allowed environments by ID, title and summary, with the active one")
    func listsEnvironments() async throws {
        let suite = temporarySuiteName("EnvironmentsReceiverTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "EnvironmentsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.environments(DebugDrawerEnvironments(default: production, allowing: staging, canary, adapter: FakeBackend(), defaults: defaults)))
        let snapshotFile = layout.snapshotFile(for: environmentsID)
        let expected = DebugDrawerEnvironments.Snapshot(
            environments: [production, staging, canary], defaultEnvironment: "production", activeEnvironment: "production"
        )
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }

        sessions.perform(.open(duration: 60))
        try sut.start()
        defer { sut.stop() }
        if !FileManager.default.fileExists(atPath: snapshotFile.path) {
            for await _ in watcher.changes where FileManager.default.fileExists(atPath: snapshotFile.path) {
                break
            }
        }

        let document = try #require(StoreDocument.decoded(from: Data(contentsOf: snapshotFile)))
        let actual = try JSONDecoder().decode(DebugDrawerEnvironments.Snapshot.self, from: document.message.payload)
        let raw = try #require(String(bytes: Data(contentsOf: snapshotFile), encoding: .utf8))
        #expect(actual == expected)
        #expect(!raw.contains("example.com"))
    }

    @Test("Only allowlisted environments are activated; an unknown or URL-shaped ID is notExposed, a command without an ID malformed")
    func onlyAllowlistedEnvironments() throws {
        let suite = temporarySuiteName("EnvironmentsReceiverTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "EnvironmentsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let backend = FakeBackend()
        let payloads: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (environmentsID, TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "https://attacker.example"))),
            (environmentsID, TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "attacker.example:443"))),
            (environmentsID, TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "qa"))),
            (environmentsID, TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "Staging"))),
            (environmentsID, Data(#"{"activate":{"url":"https://attacker.example"}}"#.utf8)),
            (environmentsID, Data(#"{"activate":{"environment":"canary","url":"https://attacker.example"}}"#.utf8)),
            (environmentsID, TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "staging")))
        ]
        for (index, (id, payload)) in payloads.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let model = DebugDrawerEnvironments(default: production, allowing: staging, canary, adapter: backend, defaults: defaults)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.environments(model))
        let expectedEvents: [DebugDrawerAuditEntry.Event] = [
            .commandRefused(.notExposed),
            .commandRefused(.notExposed),
            .commandRefused(.notExposed),
            .commandRefused(.notExposed),
            .commandRefused(.malformedCommand),
            .commandApplied,
            .commandApplied
        ]
        let expectedActivated = [canary, staging]

        try sut.start()
        defer { sut.stop() }

        let actual = sessions.auditLog.filter { $0.capability == environmentsID }.map(\.event)
        #expect(actual == expectedEvents)
        // The extra `url` key is ignored by decoding: only the listed ID is read, and the adapter
        // is handed the host's own environment, so the URL goes nowhere.
        #expect(backend.activated == expectedActivated)
        #expect(backend.baseURL == FakeBackend.baseURLs["staging"])
        #expect(model.snapshot.activeEnvironment == "staging")
    }

    @Test("As the session ends, the host's adapter is told to activate the default, audited changeReverted, and the record is removed")
    func revertsAsSessionEnds() throws {
        let suite = temporarySuiteName("EnvironmentsReceiverTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "EnvironmentsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let backend = FakeBackend()
        let payloads: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (environmentsID, TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "canary")))
        ]
        for (index, (id, payload)) in payloads.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let model = DebugDrawerEnvironments(default: production, allowing: staging, canary, adapter: backend, defaults: defaults)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.environments(model))
        try sut.start()
        defer { sut.stop() }
        let switchedDuringSession = (model.snapshot.isSwitched, sessions.snapshot.isActive, backend.baseURL)
        let recordDuringSession = defaults.string(forKey: DebugDrawerEnvironments.activeEnvironmentDefaultsKey)
        let expectedTail: [DebugDrawerAuditEntry.Event] = [.changeReverted, .sessionEnded(.ended)]

        sessions.end()

        #expect(switchedDuringSession == (true, true, FakeBackend.baseURLs["canary"]))
        #expect(recordDuringSession == "canary")
        #expect(backend.activated == [canary, production])
        #expect(backend.baseURL == FakeBackend.baseURLs["production"])
        #expect(!model.snapshot.isSwitched)
        #expect(defaults.string(forKey: DebugDrawerEnvironments.activeEnvironmentDefaultsKey) == nil)
        #expect(Array(sessions.auditLog.suffix(2).map(\.event)) == expectedTail)
    }

    @Test("As the session expires, the timer firing, the default comes back, audited before sessionEnded(.expired)")
    func revertsAsSessionExpires() throws {
        let suite = temporarySuiteName("EnvironmentsReceiverTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "EnvironmentsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let backend = FakeBackend()
        let payloads: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 3600))),
            (environmentsID, TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "staging")))
        ]
        for (index, (id, payload)) in payloads.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let clock = MovableClock(Self.now)
        let timer = ManualTimer()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: timer)
        let model = DebugDrawerEnvironments(default: production, allowing: staging, adapter: backend, defaults: defaults)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.environments(model))
        try sut.start()
        defer { sut.stop() }
        let activeDuringSession = model.snapshot.activeEnvironment
        let expectedTail: [DebugDrawerAuditEntry.Event] = [.changeReverted, .sessionEnded(.expired)]

        clock.set(Self.now.addingTimeInterval(300))
        timer.fire()

        #expect(activeDuringSession == "staging")
        #expect(backend.activated == [staging, production])
        #expect(model.snapshot.activeEnvironment == "production")
        #expect(!sessions.snapshot.isActive)
        #expect(Array(sessions.auditLog.suffix(2).map(\.event)) == expectedTail)
    }

    @Test("The capability's gate turning off puts the default back at once while the session goes on; the receiver's ends the session")
    func revertsAtGateOff() throws {
        let suite = temporarySuiteName("EnvironmentsReceiverTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "EnvironmentsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let backend = FakeBackend()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let model = DebugDrawerEnvironments(default: production, allowing: staging, adapter: backend, defaults: defaults)
        let capabilityGate = Gate()
        let receiverGate = Gate()
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions) { receiverGate.isOpen }
        sut.enable(.environments(model)) { capabilityGate.isOpen }
        try sut.start()
        defer { sut.stop() }
        sessions.perform(.open(duration: 60))

        /// Leaves a switch to staging in the store and has the receiver perform it.
        func switchToStaging(_ name: String) throws {
            let payload = try TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "staging"))
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: environmentsID, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(name).json"))
            sut.reevaluateGates()
        }
        try switchToStaging("0")
        let firstSwitch = model.snapshot.activeEnvironment
        capabilityGate.isOpen = false
        sut.reevaluateGates()
        let afterCapabilityGate = (model.snapshot.activeEnvironment, sessions.snapshot.isActive)
        capabilityGate.isOpen = true
        try switchToStaging("1")
        let secondSwitch = model.snapshot.activeEnvironment
        receiverGate.isOpen = false

        sut.reevaluateGates()

        #expect(firstSwitch == "staging")
        #expect(afterCapabilityGate == ("production", true))
        #expect(secondSwitch == "staging")
        #expect(model.snapshot.activeEnvironment == "production")
        #expect(!sessions.snapshot.isActive)
        #expect(backend.activated == [staging, production, staging, production])
        #expect(sessions.auditLog.last?.event == .sessionEnded(.disabledByHost))
    }

    @Test("A switch a session left when the app was killed is undone as the next launch makes the capability, before any session")
    func switchLeftByKillIsUndoneAtLaunch() throws {
        let suite = temporarySuiteName("EnvironmentsReceiverTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "EnvironmentsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let payload = try TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "canary"))
        try layout.write(
            StoreDocument(TransportMessage(kind: .command, pluginID: environmentsID, payload: payload)).encoded(),
            to: layout.commands.appending(path: "0.json")
        )
        let killedBackend = FakeBackend()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let killedLaunch = DebugDrawerReceiver(directory: directory, sessions: sessions)
        killedLaunch.enable(.environments(DebugDrawerEnvironments(default: production, allowing: canary, adapter: killedBackend, defaults: defaults)))
        sessions.perform(.open(duration: 60))
        try killedLaunch.start()
        // The app is killed with the session open: nothing ends it, so its revert never runs.
        killedLaunch.stop()
        let killedSwitch = killedBackend.baseURL
        // The next launch: a new process, whose backend starts wherever the host's own config puts it.
        let nextBackend = FakeBackend()
        let model = DebugDrawerEnvironments(default: production, allowing: canary, adapter: nextBackend, defaults: defaults)
        let recordedAtLaunch = model.snapshot.activeEnvironment

        _ = DebugDrawerReceiverCapability.environments(model)

        #expect(killedSwitch == FakeBackend.baseURLs["canary"])
        #expect(recordedAtLaunch == "canary")
        #expect(nextBackend.activated == [production])
        #expect(model.snapshot.activeEnvironment == "production")
        #expect(defaults.string(forKey: DebugDrawerEnvironments.activeEnvironmentDefaultsKey) == nil)
    }

    @Test("A launch that follows a clean one tells the adapter nothing as the capability is made")
    func cleanLaunchActivatesNothing() throws {
        let suite = temporarySuiteName("EnvironmentsReceiverTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = FakeBackend()
        let model = DebugDrawerEnvironments(default: production, allowing: staging, adapter: backend, defaults: defaults)

        _ = DebugDrawerReceiverCapability.environments(model)

        #expect(backend.activated.isEmpty)
        #expect(model.snapshot.activeEnvironment == "production")
    }

    @Test("Until the host enables it, a switch is refused unknownCapability in an open session; nothing is served or switched")
    func offUnlessEnabled() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "EnvironmentsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let payloads: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (environmentsID, TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "staging")))
        ]
        for (index, (id, payload)) in payloads.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let flagSuite = temporarySuiteName("EnvironmentsReceiverTests.flags")
        let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
        defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: EmptyFlagAdapter(), defaults: flagDefaults)))
        let expectedEnabled = [flagsID]

        try sut.start()
        defer { sut.stop() }

        let session = try #require(sessions.snapshot.session)
        let expectedEntry = DebugDrawerAuditEntry(
            date: Self.now, sessionID: session.id, capability: environmentsID, event: .commandRefused(.unknownCapability)
        )
        #expect(sessions.auditLog.last == expectedEntry)
        #expect(sut.enabledCapabilities == expectedEnabled)
        #expect(!FileManager.default.fileExists(atPath: layout.snapshotFile(for: environmentsID).path))
    }

    @Test("With a grant policy a switch needs a grant listing the capability: none opens no session, another's is capabilityNotGranted")
    func grantRequiredUnderPolicy() throws {
        let suite = temporarySuiteName("EnvironmentsReceiverTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "EnvironmentsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let serverKey = Curve25519.Signing.PrivateKey()
        let policy = DebugDrawerGrantPolicy(
            verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: "com.example.MyApp"
        )
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, grantPolicy: policy, clock: clock, timer: ManualTimer())
        let backend = FakeBackend()
        let model = DebugDrawerEnvironments(default: production, allowing: staging, adapter: backend, defaults: defaults)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.environments(model))
        let flagSuite = temporarySuiteName("EnvironmentsReceiverTests.flags")
        let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
        defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: EmptyFlagAdapter(), defaults: flagDefaults)))
        try sut.start()
        defer { sut.stop() }
        let signer = DebugDrawerTestGrantSigner(key: serverKey)
        let flagsOnly = try signer.token(for: DebugDrawerGrant(
            id: "g-flags", subject: "jane@example.com", audiences: ["com.example.MyApp"], capabilities: [flagsID],
            notBefore: Self.now, expires: Self.now.addingTimeInterval(120)
        ))
        let environments = try signer.token(for: DebugDrawerGrant(
            id: "g-environments", subject: "jane@example.com", audiences: ["com.example.MyApp"], capabilities: [environmentsID],
            notBefore: Self.now, expires: Self.now.addingTimeInterval(120)
        ))
        var outcomes: [DebugDrawerAuditEntry.Event] = []

        /// Leaves a switch to staging in the store, has the receiver perform it, and keeps the
        /// last audit entry.
        func switchToStaging(_ name: String) throws {
            let payload = try TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "staging"))
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: environmentsID, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(name).json"))
            sut.reevaluateGates()
            if let last = sessions.auditLog.last {
                outcomes.append(last.event)
            }
        }
        sessions.perform(.open(duration: 60))
        try switchToStaging("0")
        sessions.perform(.open(duration: 60, grant: flagsOnly))
        try switchToStaging("1")
        let activeWithFlagsGrant = model.snapshot.activeEnvironment
        sessions.perform(.end)
        sessions.perform(.open(duration: 60, grant: environments))
        try switchToStaging("2")

        #expect(outcomes == [.commandRefused(.noActiveSession), .commandRefused(.capabilityNotGranted), .commandApplied])
        #expect(activeWithFlagsGrant == "production")
        #expect(backend.activated == [staging])
        #expect(model.snapshot.activeEnvironment == "staging")
    }

    @Test("requiringGrant() refuses a switch grantMissing in a session without a grant, in a receiver with no policy")
    func requiringGrantWithoutPolicy() throws {
        let suite = temporarySuiteName("EnvironmentsReceiverTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "EnvironmentsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let payloads: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (environmentsID, TransportMessage.payload(DebugDrawerEnvironments.Command.activate(environment: "staging")))
        ]
        for (index, (id, payload)) in payloads.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let backend = FakeBackend()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let model = DebugDrawerEnvironments(default: production, allowing: staging, adapter: backend, defaults: defaults)
        sut.enable(.environments(model).requiringGrant())

        try sut.start()
        defer { sut.stop() }

        #expect(sessions.auditLog.last?.event == .commandRefused(.grantMissing))
        #expect(backend.activated.isEmpty)
    }
}
