import Combine
@testable import DebugDrawerReceiver
import Foundation
import os
import Testing

/// A flag service the test reads back: what the app would read for each flag, overrides winning.
@MainActor
private final class FakeFlagAdapter: DebugDrawerFeatureFlagAdapter {
    var live: [String: DebugDrawerFeatureFlagValue]
    private(set) var overrides: [String: DebugDrawerFeatureFlagValue] = [:]

    init(_ live: [String: DebugDrawerFeatureFlagValue]) {
        self.live = live
    }

    func overridableFlags() -> [DebugDrawerFeatureFlag] {
        live.keys.sorted().map { DebugDrawerFeatureFlag(key: $0, value: overrides[$0] ?? live[$0]!) }
    }

    func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
        overrides[key] = value
    }

    func clearOverride(forKey key: String) {
        overrides[key] = nil
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

/// The host's gate, as its remote configuration would flip it.
@MainActor
private final class HostGate {
    var isOn = true
}

/// A grant verifier that counts how often it is asked, and rejects every grant.
private final class CountingVerifier: DebugDrawerGrantVerifier {
    private let count = OSAllocatedUnfairLock(initialState: 0)

    var calls: Int {
        count.withLock { $0 }
    }

    func verify(_ token: String) throws(DebugDrawerGrantVerificationError) -> DebugDrawerGrant {
        count.withLock { $0 += 1 }
        throw .invalidSignature
    }
}

/// A wall clock that stands still.
private struct FixedClock: SessionClock {
    let now: Date
}

/// A session timer that never fires: the tests end sessions themselves.
@MainActor
private final class IdleTimer: SessionTimer {
    func schedule(at date: Date, _ fire: @escaping @MainActor () -> Void) {}
    func cancel() {}
}

// The receiver as a sidecar reaches it: each test leaves command files in the store the way a
// sidecar's transport does (a `StoreDocument` per file in `commands/`), then starts the receiver,
// which performs what waits before `start()` returns, so most tests assert with nothing to wait
// for. The audit log is the record of what was refused; the sessions log each refusal too.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ReceiverTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let flagsID = DebugDrawerFeatureFlagOverrides.pluginID
    private let sessionsID = DebugDrawerSessions.pluginID

    @Test("With no capability enabled, every command is refused, a session included, changes nothing, and is audited")
    func refusesEverythingWithNothingEnabled() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeFlagAdapter(["new-checkout": .bool(false)])
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (flagsID, TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "new-checkout", value: .bool(true)))),
            ("MyApp.LogLevels", TransportMessage.payload(LogLevelModel.Command.set("debug")))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let expectedLog = [
            DebugDrawerAuditEntry(date: Self.now, sessionID: nil, capability: sessionsID, event: .commandRefused(.unknownCapability)),
            DebugDrawerAuditEntry(date: Self.now, sessionID: nil, capability: flagsID, event: .commandRefused(.unknownCapability)),
            DebugDrawerAuditEntry(date: Self.now, sessionID: nil, capability: "MyApp.LogLevels", event: .commandRefused(.unknownCapability))
        ]

        try sut.start()
        defer { sut.stop() }

        #expect(sessions.auditLog == expectedLog)
        #expect(sessions.snapshot == .inactive)
        #expect(adapter.overrides.isEmpty)
        #expect(sut.enabledCapabilities.isEmpty)
        #expect(layout.messageFiles(in: layout.commands).isEmpty)
    }

    @Test("A capability the host didn't enable stays refused inside an open session, while an enabled one is applied")
    func unenabledRefusedInsideSession() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeFlagAdapter(["new-checkout": .bool(false)])
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            ("MyApp.LogLevels", TransportMessage.payload(LogLevelModel.Command.set("debug"))),
            (flagsID, TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "new-checkout", value: .bool(true))))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let flagSuite = "ReceiverTests.flags.\(UUID().uuidString)"
        let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
        defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: adapter, defaults: flagDefaults)))
        let expectedOverrides: [String: DebugDrawerFeatureFlagValue] = ["new-checkout": .bool(true)]

        try sut.start()
        defer { sut.stop() }

        let session = try #require(sessions.snapshot.session)
        let expectedLog = [
            DebugDrawerAuditEntry(
                date: Self.now, sessionID: session.id, capability: sessionsID,
                event: .sessionOpened(expires: Self.now.addingTimeInterval(60))
            ),
            DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: "MyApp.LogLevels", event: .commandRefused(.unknownCapability)),
            DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: flagsID, event: .commandApplied)
        ]
        #expect(sessions.auditLog == expectedLog)
        #expect(adapter.overrides == expectedOverrides)
    }

    @Test("An enabled capability's command outside a session is refused and changes nothing")
    func refusedOutsideSession() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let logLevels = LogLevelModel()
        let payload = try TransportMessage.payload(LogLevelModel.Command.set("debug"))
        let document = StoreDocument(TransportMessage(kind: .command, pluginID: "MyApp.LogLevels", payload: payload))
        try layout.write(document.encoded(), to: layout.commands.appending(path: "0.json"))
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.model(logLevels, id: "MyApp.LogLevels", scope: .session(revertWith: .reset)))
        let expectedLog = [
            DebugDrawerAuditEntry(date: Self.now, sessionID: nil, capability: "MyApp.LogLevels", event: .commandRefused(.noActiveSession))
        ]

        try sut.start()
        defer { sut.stop() }

        #expect(sessions.auditLog == expectedLog)
        #expect(logLevels.snapshot == LogLevelModel.Snapshot())
    }

    @Test("A disabled capability's commands are refused, and its snapshot leaves the store")
    func disabledIsRefused() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let logLevels = LogLevelModel()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.model(logLevels, id: "MyApp.LogLevels", scope: .persistent))
        let flagSuite = "ReceiverTests.flags.\(UUID().uuidString)"
        let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
        defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: FakeFlagAdapter([:]), defaults: flagDefaults)))
        sessions.perform(.open(duration: 60))
        let snapshotFile = layout.snapshotFile(for: "MyApp.LogLevels")
        try sut.start()
        defer { sut.stop() }
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        if !FileManager.default.fileExists(atPath: snapshotFile.path) {
            for await _ in watcher.changes where FileManager.default.fileExists(atPath: snapshotFile.path) {
                break
            }
        }
        let (arrivals, arrival) = AsyncStream<DebugDrawerAuditEntry>.makeStream()
        let subscription = sessions.auditEntries.sink { arrival.yield($0) }
        defer { subscription.cancel() }
        let payload = try TransportMessage.payload(LogLevelModel.Command.set("debug"))
        let document = StoreDocument(TransportMessage(kind: .command, pluginID: "MyApp.LogLevels", payload: payload))
        let session = try #require(sessions.snapshot.session)
        let expected = DebugDrawerAuditEntry(
            date: Self.now, sessionID: session.id, capability: "MyApp.LogLevels", event: .commandRefused(.unknownCapability)
        )
        let expectedEnabled = [flagsID]

        sut.disable("MyApp.LogLevels")
        try layout.write(document.encoded(), to: layout.commands.appending(path: "0.json"))
        var actual: DebugDrawerAuditEntry?
        for await recorded in arrivals {
            actual = recorded
            break
        }

        #expect(actual == expected)
        #expect(logLevels.snapshot == LogLevelModel.Snapshot())
        #expect(sut.enabledCapabilities == expectedEnabled)
        #expect(!FileManager.default.fileExists(atPath: snapshotFile.path))
    }

    @Test("Ending the session clears the overrides a sidecar set, by default, and audits the revert")
    func sessionEndRevertsOverrides() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeFlagAdapter(["new-checkout": .bool(false), "button-color": .string("blue")])
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (flagsID, TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "button-color", value: .string("green"))))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let flagSuite = "ReceiverTests.flags.\(UUID().uuidString)"
        let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
        defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: adapter, defaults: flagDefaults)))
        try sut.start()
        defer { sut.stop() }
        let session = try #require(sessions.snapshot.session)
        let expectedTail = [
            DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: flagsID, event: .changeReverted),
            DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: sessionsID, event: .sessionEnded(.ended))
        ]

        sessions.end()

        #expect(adapter.overrides.isEmpty)
        #expect(Array(sessions.auditLog.suffix(2)) == expectedTail)
    }

    @Test("A command that isn't one of the capability's commands is refused as malformed")
    func malformedCommandRefused() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeFlagAdapter(["new-checkout": .bool(false)])
        let document = StoreDocument(TransportMessage(kind: .command, pluginID: flagsID, payload: Data(#"{"runScript":{"source":"exit(0)"}}"#.utf8)))
        try layout.write(document.encoded(), to: layout.commands.appending(path: "0.json"))
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let flagSuite = "ReceiverTests.flags.\(UUID().uuidString)"
        let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
        defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: adapter, defaults: flagDefaults)))
        sessions.perform(.open(duration: 60))
        let session = try #require(sessions.snapshot.session)
        let expected = DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: flagsID, event: .commandRefused(.malformedCommand))

        try sut.start()
        defer { sut.stop() }

        #expect(sessions.auditLog.last == expected)
        #expect(adapter.overrides.isEmpty)
    }

    @Test("Starting with a session open writes the sessions' and each enabled capability's snapshot, and removes any other snapshot file")
    func writesOnlyServedSnapshots() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let stale = layout.snapshotFile(for: "MyApp.Keychain")
        try Data("{}".utf8).write(to: stale)
        let adapter = FakeFlagAdapter(["new-checkout": .bool(false)])
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let flagSuite = "ReceiverTests.flags.\(UUID().uuidString)"
        let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
        defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: adapter, defaults: flagDefaults)))
        let expectedFiles = [layout.snapshotFile(for: sessionsID), layout.snapshotFile(for: flagsID)].map(\.lastPathComponent).sorted()
        let expectedFlags = DebugDrawerFeatureFlagOverrides.Snapshot(
            flags: [DebugDrawerFeatureFlag(key: "new-checkout", value: .bool(false))], overriddenKeys: []
        )
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        sessions.perform(.open(duration: 60))

        try sut.start()
        defer { sut.stop() }
        if layout.messageFiles(in: layout.snapshots).count < 2 {
            for await _ in watcher.changes where layout.messageFiles(in: layout.snapshots).count >= 2 {
                break
            }
        }

        let actualFiles = layout.messageFiles(in: layout.snapshots).map(\.lastPathComponent).sorted()
        #expect(actualFiles == expectedFiles)
        let document = try #require(StoreDocument.decoded(from: Data(contentsOf: layout.snapshotFile(for: flagsID))))
        let actualFlags = try JSONDecoder().decode(DebugDrawerFeatureFlagOverrides.Snapshot.self, from: document.message.payload)
        #expect(document.message.kind == .snapshot)
        #expect(actualFlags == expectedFlags)
    }

    @Test("The host's gate, off as the app comes to the foreground, ends the open session as disabledByHost and reverts its changes")
    func gateOffAtForegroundEndsSession() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverTests-\(UUID().uuidString)")
        let logLevels = LogLevelModel()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let gate = HostGate()
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions) { gate.isOn }
        let center = NotificationCenter()
        sut.notificationCenter = center
        sut.enable(.model(logLevels, id: "MyApp.LogLevels", scope: .session(revertWith: .reset)))
        try sut.start()
        defer { sut.stop() }
        sessions.perform(.open(duration: 60))
        let session = try #require(sessions.snapshot.session)
        sessions.apply(to: "MyApp.LogLevels", scope: .session { logLevels.perform(.reset) }) {
            logLevels.perform(.set("debug"))
            return true
        }
        let expectedTail = [
            DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: "MyApp.LogLevels", event: .changeReverted),
            DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: sessionsID, event: .sessionEnded(.disabledByHost))
        ]

        gate.isOn = false
        center.post(name: DebugDrawerReceiver.foreground, object: nil)

        #expect(Array(sessions.auditLog.suffix(2)) == expectedTail)
        #expect(sessions.snapshot == .inactive)
        #expect(logLevels.snapshot == LogLevelModel.Snapshot())
    }

    @Test("The host gate comes before grants: off, a session asked for with a grant is refused as receiverDisabled, the verifier unasked")
    func gateBeforeGrant() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let verifier = CountingVerifier()
        let policy = DebugDrawerGrantPolicy(verifier: verifier, audience: "com.example.MyApp")
        let sessions = DebugDrawerSessions(
            maximumDuration: 300, auditCapacity: 100, grantPolicy: policy, clock: FixedClock(now: Self.now), timer: IdleTimer()
        )
        let gate = HostGate()
        gate.isOn = false
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions) { gate.isOn }
        sut.enable(.model(LogLevelModel(), id: "MyApp.LogLevels", scope: .session(revertWith: .reset)))
        let payload = try TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60, grant: "a-grant"))
        let document = StoreDocument(TransportMessage(kind: .command, pluginID: sessionsID, payload: payload))
        try layout.write(document.encoded(), to: layout.commands.appending(path: "0.json"))
        let expectedLog = [
            DebugDrawerAuditEntry(date: Self.now, sessionID: nil, capability: sessionsID, event: .commandRefused(.receiverDisabled))
        ]

        try sut.start()
        defer { sut.stop() }

        #expect(sessions.auditLog == expectedLog)
        #expect(verifier.calls == 0)
        #expect(sessions.snapshot == .inactive)
    }

    @Test("Starting throws cannotServe, and serves nothing, where the store's directory can't be made")
    func cannotServe() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "ReceiverTests-\(UUID().uuidString)")
        try Data().write(to: file)
        let sut = DebugDrawerReceiver(directory: file.appending(path: "DebugDrawer"), sessions: DebugDrawerSessions(maximumDuration: 300))

        #expect(throws: DebugDrawerReceiverError.cannotServe) {
            try sut.start()
        }
        #expect(!sut.isRunning)
    }
}
