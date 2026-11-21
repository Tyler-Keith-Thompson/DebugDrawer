@testable import DebugDrawerReceiver
import Foundation
import Testing

/// A flag service the test reads back, standing in for one that keeps its overrides across
/// launches: the same instance is handed to the receiver of each launch.
@MainActor
private final class FakeFlagAdapter: DebugDrawerFeatureFlagAdapter {
    let live: [String: DebugDrawerFeatureFlagValue]
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

// The feature flag overrides capability end to end through the receiver alone, as a release build
// links it (no drawer): what a sidecar may override, when a command it left lands, what the audit
// log records, and what outlives a session and a launch. Commands are files left in the store the
// way a sidecar's transport leaves them; the receiver performs those waiting as it starts, so most
// tests assert with nothing to wait for. Each test keeps the model's record of what it overrode in
// a defaults suite of its own.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct FeatureFlagOverridesReceiverTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let flagsID = DebugDrawerFeatureFlagOverrides.pluginID
    private let sessionsID = DebugDrawerSessions.pluginID

    @Test("Only a listed flag is overridden: an unlisted one is refused notExposed, a value of another kind malformedCommand")
    func onlyListedFlagsChange() throws {
        let suite = "FeatureFlagOverridesReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "FeatureFlagOverridesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeFlagAdapter(["new-checkout": .bool(false)])
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (flagsID, TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "server-tier", value: .string("premium")))),
            (flagsID, TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "new-checkout", value: .string("true")))),
            (flagsID, TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.clearOverride(key: "server-tier"))),
            (flagsID, TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "new-checkout", value: .bool(true))))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let model = DebugDrawerFeatureFlagOverrides(adapter: adapter, defaults: defaults)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.featureFlagOverrides(model))
        let expectedOverrides: [String: DebugDrawerFeatureFlagValue] = ["new-checkout": .bool(true)]
        let expectedEvents: [DebugDrawerAuditEntry.Event] = [
            .commandRefused(.notExposed),
            .commandRefused(.malformedCommand),
            .commandRefused(.notExposed),
            .commandApplied
        ]
        let expectedKeys = ["new-checkout"]

        try sut.start()
        defer { sut.stop() }

        let actual = sessions.auditLog.filter { $0.capability == flagsID }
        #expect(adapter.overrides == expectedOverrides)
        #expect(actual.map(\.event) == expectedEvents)
        #expect(model.snapshot.overriddenKeys == expectedKeys)
    }

    @Test("An override a sidecar leaves while the app is in the background is applied as it comes to the foreground, with only the receiver linked")
    func appliesOnForeground() throws {
        let suite = "FeatureFlagOverridesReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "FeatureFlagOverridesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        let adapter = FakeFlagAdapter(["new-checkout": .bool(false)])
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let center = NotificationCenter()
        sut.notificationCenter = center
        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: adapter, defaults: defaults)))
        try sut.start()
        defer { sut.stop() }
        sessions.perform(.open(duration: 60))
        let session = try #require(sessions.snapshot.session)
        let payload = try TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "new-checkout", value: .bool(true)))
        let document = StoreDocument(TransportMessage(kind: .command, pluginID: flagsID, payload: payload))
        let expectedOverrides: [String: DebugDrawerFeatureFlagValue] = ["new-checkout": .bool(true)]
        let expectedEntry = DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: flagsID, event: .commandApplied)

        // Nothing awaits from here on, so the main actor runs none of the receiver's own work, as
        // for an app the system has suspended: the store's wake-up can't perform the override,
        // only the foreground can.
        try layout.write(document.encoded(), to: layout.commands.appending(path: "0.json"))
        let whileInBackground = adapter.overrides
        center.post(name: DebugDrawerReceiver.foreground, object: nil)

        #expect(whileInBackground.isEmpty)
        #expect(adapter.overrides == expectedOverrides)
        #expect(sessions.auditLog.last == expectedEntry)
    }

    @Test("Each override, each clear and the session's revert leaves its own audit entry naming the capability and the session")
    func auditsEachOverride() throws {
        let suite = "FeatureFlagOverridesReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "FeatureFlagOverridesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeFlagAdapter(["new-checkout": .bool(false), "button-color": .string("blue")])
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (flagsID, TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "new-checkout", value: .bool(true)))),
            (flagsID, TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "button-color", value: .string("green")))),
            (flagsID, TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.clearOverride(key: "new-checkout")))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: adapter, defaults: defaults)))
        try sut.start()
        defer { sut.stop() }
        let session = try #require(sessions.snapshot.session)
        let expected = [
            DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: sessionsID, event: .sessionOpened(expires: session.expires)),
            DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: flagsID, event: .commandApplied),
            DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: flagsID, event: .commandApplied),
            DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: flagsID, event: .commandApplied),
            DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: flagsID, event: .changeReverted),
            DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: sessionsID, event: .sessionEnded(.ended))
        ]

        sessions.end()

        #expect(sessions.auditLog == expected)
        #expect(adapter.overrides.isEmpty)
    }

    @Test("Persistent overrides outlive the session and a relaunch of an adapter that keeps them; the next launch lists and clears them")
    func persistentOverridesSurviveRelaunch() throws {
        let suite = "FeatureFlagOverridesReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "FeatureFlagOverridesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeFlagAdapter(["new-checkout": .bool(false)])
        let set = try TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "new-checkout", value: .bool(true)))
        let setDocument = StoreDocument(TransportMessage(kind: .command, pluginID: flagsID, payload: set))
        try layout.write(setDocument.encoded(), to: layout.commands.appending(path: "0.json"))
        let firstSessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let firstLaunch = DebugDrawerReceiver(directory: directory, sessions: firstSessions)
        firstLaunch.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: adapter, defaults: defaults), scope: .persistent))
        firstSessions.perform(.open(duration: 60))
        try firstLaunch.start()
        firstSessions.end()
        firstLaunch.stop()
        let afterFirstLaunch = adapter.overrides
        let clear = try TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.clearOverride(key: "new-checkout"))
        let clearDocument = StoreDocument(TransportMessage(kind: .command, pluginID: flagsID, payload: clear))
        try layout.write(clearDocument.encoded(), to: layout.commands.appending(path: "1.json"))
        let secondSessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let model = DebugDrawerFeatureFlagOverrides(adapter: adapter, defaults: defaults)
        let listedAtRelaunch = model.snapshot.overriddenKeys
        let sut = DebugDrawerReceiver(directory: directory, sessions: secondSessions)
        sut.enable(.featureFlagOverrides(model, scope: .persistent))
        secondSessions.perform(.open(duration: 60))
        let expectedOverrides: [String: DebugDrawerFeatureFlagValue] = ["new-checkout": .bool(true)]
        let expectedKeys = ["new-checkout"]

        try sut.start()
        defer { sut.stop() }

        #expect(afterFirstLaunch == expectedOverrides)
        #expect(listedAtRelaunch == expectedKeys)
        #expect(adapter.overrides.isEmpty)
        #expect(model.snapshot.overriddenKeys.isEmpty)
        #expect(secondSessions.auditLog.last?.event == .commandApplied)
    }

    @Test("With the default scope, overrides a session left when the app quit during it are cleared as the next launch makes the capability")
    func sessionOverridesLeftByQuitAreCleared() throws {
        let suite = "FeatureFlagOverridesReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "FeatureFlagOverridesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeFlagAdapter(["new-checkout": .bool(false), "promo": .bool(false)])
        adapter.setOverride(.bool(true), forKey: "promo")
        let set = try TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "new-checkout", value: .bool(true)))
        let setDocument = StoreDocument(TransportMessage(kind: .command, pluginID: flagsID, payload: set))
        try layout.write(setDocument.encoded(), to: layout.commands.appending(path: "0.json"))
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let quitLaunch = DebugDrawerReceiver(directory: directory, sessions: sessions)
        quitLaunch.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: adapter, defaults: defaults)))
        sessions.perform(.open(duration: 60))
        try quitLaunch.start()
        // The app quits with the session open: nothing ends it, so its revert never runs.
        quitLaunch.stop()
        let afterQuit = adapter.overrides
        let model = DebugDrawerFeatureFlagOverrides(adapter: adapter, defaults: defaults)
        let expectedAfterQuit: [String: DebugDrawerFeatureFlagValue] = ["new-checkout": .bool(true), "promo": .bool(true)]
        let expectedOverrides: [String: DebugDrawerFeatureFlagValue] = ["promo": .bool(true)]

        _ = DebugDrawerReceiverCapability.featureFlagOverrides(model)

        #expect(afterQuit == expectedAfterQuit)
        #expect(adapter.overrides == expectedOverrides)
        #expect(model.snapshot.overriddenKeys.isEmpty)
    }
}
