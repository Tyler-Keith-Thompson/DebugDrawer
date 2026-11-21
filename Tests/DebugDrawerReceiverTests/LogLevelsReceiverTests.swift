@testable import DebugDrawerReceiver
import Foundation
import os
import Testing

/// A logger the test reads back: its levels per subsystem, and every call the receiver made to it,
/// in order. The same instance is handed to the receiver of each launch, standing in for a logger
/// whose configuration outlives the process.
@MainActor
private final class FakeLogLevelAdapter: DebugDrawerLogLevelAdapter {
    enum Call: Equatable {
        case set(subsystem: String, level: String)
        case reset(subsystem: String)
    }

    let subsystems: [String: [String]]
    let defaultLevel: String
    private(set) var levels: [String: String] = [:]
    private(set) var calls: [Call] = []

    init(subsystems: [String: [String]], defaultLevel: String) {
        self.subsystems = subsystems
        self.defaultLevel = defaultLevel
    }

    func elevatableSubsystems() -> [DebugDrawerLogSubsystem] {
        subsystems.keys.sorted().map { name in
            DebugDrawerLogSubsystem(name: name, levels: subsystems[name]!, level: levels[name] ?? defaultLevel)
        }
    }

    func setLevel(_ level: String, forSubsystem subsystem: String) {
        levels[subsystem] = level
        calls.append(.set(subsystem: subsystem, level: level))
    }

    func resetLevel(forSubsystem subsystem: String) {
        levels[subsystem] = nil
        calls.append(.reset(subsystem: subsystem))
    }
}

/// A flag service with nothing to override, so a receiver serves a capability other than log
/// levels.
@MainActor
private final class EmptyFlagAdapter: DebugDrawerFeatureFlagAdapter {
    func overridableFlags() -> [DebugDrawerFeatureFlag] { [] }
    func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {}
    func clearOverride(forKey key: String) {}
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

// The log levels capability end to end through the receiver alone, as a release build links it
// (no drawer): what a sidecar sees, which levels the host's logger is told to set and reset per
// subsystem, that every raised level is reset as the session ends or expires (and at the next
// launch, after a kill), and that nothing is served until the host enables it. Commands are files
// left in the store the way a sidecar's transport leaves them; the receiver performs those waiting
// as it starts. Sessions run on a clock the test moves and a timer it fires, so expiry is exact
// and nothing waits. Each test keeps the model's record of what it raised in a defaults suite of
// its own.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LogLevelsReceiverTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let logLevelsID = DebugDrawerLogLevels.pluginID
    private let flagsID = DebugDrawerFeatureFlagOverrides.pluginID
    private let sessionsID = DebugDrawerSessions.pluginID

    @Test("A sidecar reads, from the store, each subsystem the adapter lists with the levels it may set and its level now")
    func listsSubsystemsWithLevels() async throws {
        let suite = "LogLevelsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "LogLevelsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeLogLevelAdapter(
            subsystems: ["com.example.checkout": ["info", "debug", "trace"], "com.example.sync": ["info", "debug"]],
            defaultLevel: "info"
        )
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.logLevels(DebugDrawerLogLevels(adapter: adapter, defaults: defaults)))
        let snapshotFile = layout.snapshotFile(for: logLevelsID)
        let expected = DebugDrawerLogLevels.Snapshot(
            subsystems: [
                DebugDrawerLogSubsystem(name: "com.example.checkout", levels: ["info", "debug", "trace"], level: "info"),
                DebugDrawerLogSubsystem(name: "com.example.sync", levels: ["info", "debug"], level: "info")
            ],
            raisedSubsystems: []
        )
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }

        try sut.start()
        defer { sut.stop() }
        if !FileManager.default.fileExists(atPath: snapshotFile.path) {
            for await _ in watcher.changes where FileManager.default.fileExists(atPath: snapshotFile.path) {
                break
            }
        }

        let document = try #require(StoreDocument.decoded(from: Data(contentsOf: snapshotFile)))
        let actual = try JSONDecoder().decode(DebugDrawerLogLevels.Snapshot.self, from: document.message.payload)
        #expect(document.message.kind == .snapshot)
        #expect(actual == expected)
    }

    @Test("The host's logger hears each level set and reset per subsystem, in order; an unlisted subsystem: notExposed, level: malformed")
    func hostHearsEachLevelChangePerSubsystem() throws {
        let suite = "LogLevelsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "LogLevelsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeLogLevelAdapter(
            subsystems: ["com.example.checkout": ["info", "debug", "trace"], "com.example.sync": ["info", "debug"]],
            defaultLevel: "info"
        )
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (logLevelsID, TransportMessage.payload(DebugDrawerLogLevels.Command.setLevel(subsystem: "com.example.checkout", level: "debug"))),
            (logLevelsID, TransportMessage.payload(DebugDrawerLogLevels.Command.setLevel(subsystem: "com.example.payments", level: "debug"))),
            (logLevelsID, TransportMessage.payload(DebugDrawerLogLevels.Command.setLevel(subsystem: "com.example.sync", level: "trace"))),
            (logLevelsID, TransportMessage.payload(DebugDrawerLogLevels.Command.setLevel(subsystem: "com.example.sync", level: "debug"))),
            (logLevelsID, TransportMessage.payload(DebugDrawerLogLevels.Command.setLevel(subsystem: "com.example.checkout", level: "trace"))),
            (logLevelsID, TransportMessage.payload(DebugDrawerLogLevels.Command.reset(subsystem: "com.example.payments"))),
            (logLevelsID, TransportMessage.payload(DebugDrawerLogLevels.Command.reset(subsystem: "com.example.sync")))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let model = DebugDrawerLogLevels(adapter: adapter, defaults: defaults)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.logLevels(model))
        let expectedCalls: [FakeLogLevelAdapter.Call] = [
            .set(subsystem: "com.example.checkout", level: "debug"),
            .set(subsystem: "com.example.sync", level: "debug"),
            .set(subsystem: "com.example.checkout", level: "trace"),
            .reset(subsystem: "com.example.sync")
        ]
        let expectedEvents: [DebugDrawerAuditEntry.Event] = [
            .commandApplied,
            .commandRefused(.notExposed),
            .commandRefused(.malformedCommand),
            .commandApplied,
            .commandApplied,
            .commandRefused(.notExposed),
            .commandApplied
        ]
        let expectedLevels = ["com.example.checkout": "trace"]
        let expectedRaised = ["com.example.checkout"]

        try sut.start()
        defer { sut.stop() }

        let actual = sessions.auditLog.filter { $0.capability == logLevelsID }
        #expect(adapter.calls == expectedCalls)
        #expect(actual.map(\.event) == expectedEvents)
        #expect(adapter.levels == expectedLevels)
        #expect(model.snapshot.raisedSubsystems == expectedRaised)
    }

    @Test("As the session ends, the host's logger is told to reset each subsystem the sidecar raised, and only those, audited changeReverted")
    func levelsResetAsSessionEnds() throws {
        let suite = "LogLevelsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "LogLevelsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeLogLevelAdapter(
            subsystems: ["com.example.checkout": ["info", "debug"], "com.example.sync": ["info", "debug"], "com.example.ui": ["info", "debug"]],
            defaultLevel: "info"
        )
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (logLevelsID, TransportMessage.payload(DebugDrawerLogLevels.Command.setLevel(subsystem: "com.example.sync", level: "debug"))),
            (logLevelsID, TransportMessage.payload(DebugDrawerLogLevels.Command.setLevel(subsystem: "com.example.checkout", level: "debug")))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let model = DebugDrawerLogLevels(adapter: adapter, defaults: defaults)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.logLevels(model))
        try sut.start()
        defer { sut.stop() }
        let callsBeforeEnd = adapter.calls.count
        let expectedResets: [FakeLogLevelAdapter.Call] = [.reset(subsystem: "com.example.checkout"), .reset(subsystem: "com.example.sync")]
        let expectedTail: [DebugDrawerAuditEntry.Event] = [.changeReverted, .sessionEnded(.ended)]

        sessions.end()

        #expect(Array(adapter.calls.dropFirst(callsBeforeEnd)) == expectedResets)
        #expect(adapter.levels.isEmpty)
        #expect(model.snapshot.raisedSubsystems.isEmpty)
        #expect(defaults.stringArray(forKey: DebugDrawerLogLevels.raisedSubsystemsDefaultsKey) == nil)
        #expect(Array(sessions.auditLog.suffix(2).map(\.event)) == expectedTail)
    }

    @Test("As the session expires at its maximum duration, the timer firing, every raised level is reset, audited before sessionEnded(.expired)")
    func levelsResetAsSessionExpires() throws {
        let suite = "LogLevelsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "LogLevelsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeLogLevelAdapter(subsystems: ["com.example.checkout": ["info", "debug"]], defaultLevel: "info")
        // The sidecar asks for longer than the maximum, so the session expires at the maximum.
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 3600))),
            (logLevelsID, TransportMessage.payload(DebugDrawerLogLevels.Command.setLevel(subsystem: "com.example.checkout", level: "debug")))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let clock = MovableClock(Self.now)
        let timer = ManualTimer()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: timer)
        let model = DebugDrawerLogLevels(adapter: adapter, defaults: defaults)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.logLevels(model))
        try sut.start()
        defer { sut.stop() }
        let raisedDuringSession = adapter.levels
        let expiry = Self.now.addingTimeInterval(300)
        let scheduled = timer.scheduled
        let expectedLastCall = FakeLogLevelAdapter.Call.reset(subsystem: "com.example.checkout")
        let expectedTail: [DebugDrawerAuditEntry.Event] = [.changeReverted, .sessionEnded(.expired)]

        clock.set(expiry)
        timer.fire()

        #expect(raisedDuringSession == ["com.example.checkout": "debug"])
        #expect(scheduled == expiry)
        #expect(adapter.calls.last == expectedLastCall)
        #expect(adapter.levels.isEmpty)
        #expect(model.snapshot.raisedSubsystems.isEmpty)
        #expect(!sessions.snapshot.isActive)
        #expect(Array(sessions.auditLog.suffix(2).map(\.event)) == expectedTail)
    }

    @Test("An expiry the timer missed (a suspended app) resets the levels at the next command, which is then refused noActiveSession")
    func levelsResetWhenExpiryFoundLate() throws {
        let suite = "LogLevelsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "LogLevelsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeLogLevelAdapter(subsystems: ["com.example.checkout": ["info", "debug", "trace"]], defaultLevel: "info")
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let model = DebugDrawerLogLevels(adapter: adapter, defaults: defaults)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.logLevels(model))
        sessions.perform(.open(duration: 60))
        let raise = try TransportMessage.payload(DebugDrawerLogLevels.Command.setLevel(subsystem: "com.example.checkout", level: "debug"))
        try layout.write(
            StoreDocument(TransportMessage(kind: .command, pluginID: logLevelsID, payload: raise)).encoded(),
            to: layout.commands.appending(path: "0.json")
        )
        try sut.start()
        defer { sut.stop() }
        let raisedDuringSession = adapter.levels
        clock.set(Self.now.addingTimeInterval(61))
        let late = try TransportMessage.payload(DebugDrawerLogLevels.Command.setLevel(subsystem: "com.example.checkout", level: "trace"))
        try layout.write(
            StoreDocument(TransportMessage(kind: .command, pluginID: logLevelsID, payload: late)).encoded(),
            to: layout.commands.appending(path: "1.json")
        )
        let expectedTail: [DebugDrawerAuditEntry.Event] = [.changeReverted, .sessionEnded(.expired), .commandRefused(.noActiveSession)]
        let expectedCalls: [FakeLogLevelAdapter.Call] = [
            .set(subsystem: "com.example.checkout", level: "debug"),
            .reset(subsystem: "com.example.checkout")
        ]

        sut.reevaluateGates()

        #expect(raisedDuringSession == ["com.example.checkout": "debug"])
        #expect(adapter.calls == expectedCalls)
        #expect(adapter.levels.isEmpty)
        #expect(Array(sessions.auditLog.suffix(3).map(\.event)) == expectedTail)
    }

    @Test("Levels a session raised before the app was killed are reset as the next launch makes the capability")
    func levelsLeftByKillAreResetAtLaunch() throws {
        let suite = "LogLevelsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "LogLevelsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeLogLevelAdapter(subsystems: ["com.example.checkout": ["info", "debug"]], defaultLevel: "info")
        let raise = try TransportMessage.payload(DebugDrawerLogLevels.Command.setLevel(subsystem: "com.example.checkout", level: "debug"))
        try layout.write(
            StoreDocument(TransportMessage(kind: .command, pluginID: logLevelsID, payload: raise)).encoded(),
            to: layout.commands.appending(path: "0.json")
        )
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let killedLaunch = DebugDrawerReceiver(directory: directory, sessions: sessions)
        killedLaunch.enable(.logLevels(DebugDrawerLogLevels(adapter: adapter, defaults: defaults)))
        sessions.perform(.open(duration: 60))
        try killedLaunch.start()
        // The app is killed with the session open: nothing ends it, so its reset never runs.
        killedLaunch.stop()
        let afterKill = adapter.levels
        let model = DebugDrawerLogLevels(adapter: adapter, defaults: defaults)
        let raisedAtLaunch = model.snapshot.raisedSubsystems
        let expectedAfterKill = ["com.example.checkout": "debug"]
        let expectedRaisedAtLaunch = ["com.example.checkout"]

        _ = DebugDrawerReceiverCapability.logLevels(model)

        #expect(afterKill == expectedAfterKill)
        #expect(raisedAtLaunch == expectedRaisedAtLaunch)
        #expect(adapter.calls.last == .reset(subsystem: "com.example.checkout"))
        #expect(adapter.levels.isEmpty)
        #expect(model.snapshot.raisedSubsystems.isEmpty)
    }

    @Test("Until the host enables it, a command to it is refused unknownCapability in an open session; nothing is served or raised")
    func offUnlessEnabled() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "LogLevelsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeLogLevelAdapter(subsystems: ["com.example.checkout": ["info", "debug"]], defaultLevel: "info")
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (logLevelsID, TransportMessage.payload(DebugDrawerLogLevels.Command.setLevel(subsystem: "com.example.checkout", level: "debug")))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let flagSuite = "LogLevelsReceiverTests.flags.\(UUID().uuidString)"
        let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
        defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: EmptyFlagAdapter(), defaults: flagDefaults)))
        let expectedEnabled = [flagsID]

        try sut.start()
        defer { sut.stop() }

        let session = try #require(sessions.snapshot.session)
        let expectedEntry = DebugDrawerAuditEntry(
            date: Self.now, sessionID: session.id, capability: logLevelsID, event: .commandRefused(.unknownCapability)
        )
        #expect(sessions.auditLog.last == expectedEntry)
        #expect(adapter.calls.isEmpty)
        #expect(sut.enabledCapabilities == expectedEnabled)
        #expect(!FileManager.default.fileExists(atPath: layout.snapshotFile(for: logLevelsID).path))
    }
}
