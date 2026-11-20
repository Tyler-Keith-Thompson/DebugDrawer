import CryptoKit
@testable import DebugDrawerReceiver
import Foundation
import os
import Testing

/// A flag service with nothing to override, so a receiver serves a capability other than
/// UserDefaults.
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

// Allowlisted UserDefaults end to end through the receiver alone, as a release build links it (no
// drawer): a sidecar reads only the keys the host lists and edits only those, within each key's
// kind; any other key is refused and stays as it was; nothing is served or edited until the host
// enables it; each edit's audit entry carries the key with its value before and after; and the
// edits are put back as the session ends, expires, a gate turns off, or the next launch follows a
// kill. Commands are files left in the store the way a sidecar's transport leaves them; the
// receiver performs those waiting as it starts or re-evaluates its gates. Sessions run on a clock
// the test moves and a timer it fires. Each test keeps its keys in a defaults suite of its own.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct UserDefaultsReceiverTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let defaultsID = DebugDrawerUserDefaults.pluginID
    private let flagsID = DebugDrawerFeatureFlagOverrides.pluginID
    private let sessionsID = DebugDrawerSessions.pluginID
    private let allowlist: [DebugDrawerUserDefaultsKey] = [
        .choice("plan", title: "Plan", options: ["free", "pro"]),
        .bool("showsTips", title: "Shows Tips"),
        .integer("itemsPerPage", title: "Items per Page", in: 10 ... 100),
        .double("discount", in: 0 ... 0.5),
        .string("greeting", maximumLength: 12)
    ]

    @Test("A sidecar reads, from the store, the allowlisted keys with their values as their kinds, and no other key of the domain")
    func listsOnlyAllowlistedKeys() async throws {
        let suite = "UserDefaultsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("pro", forKey: "plan")
        defaults.set(25, forKey: "itemsPerPage")
        defaults.set(Data([1, 2, 3]), forKey: "greeting")
        defaults.set("secret-session-token-4417", forKey: "sessionToken")
        let directory = FileManager.default.temporaryDirectory.appending(path: "UserDefaultsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.userDefaults(DebugDrawerUserDefaults(keys: allowlist, defaults: defaults)))
        let snapshotFile = layout.snapshotFile(for: defaultsID)
        let expected = DebugDrawerUserDefaults.Snapshot(
            entries: [
                .init(key: "plan", title: "Plan", kind: .choice(options: ["free", "pro"]), value: .string("pro")),
                .init(key: "showsTips", title: "Shows Tips", kind: .bool, value: nil),
                .init(key: "itemsPerPage", title: "Items per Page", kind: .integer(range: 10 ... 100), value: .integer(25)),
                .init(key: "discount", title: "discount", kind: .double(range: 0 ... 0.5), value: nil),
                // Data under a string key is of another kind: it reads as none.
                .init(key: "greeting", title: "greeting", kind: .string(maximumLength: 12), value: nil)
            ],
            editedKeys: []
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
        let actual = try JSONDecoder().decode(DebugDrawerUserDefaults.Snapshot.self, from: document.message.payload)
        let payload = try #require(String(bytes: document.message.payload, encoding: .utf8))
        #expect(actual == expected)
        #expect(!payload.contains("sessionToken"))
        #expect(!payload.contains("secret-session-token-4417"))
    }

    @Test("Only allowlisted keys are edited: another key is notExposed, a value the key's kind doesn't take malformed, and neither changes anything")
    func onlyAllowlistedKeysAreEdited() throws {
        let suite = "UserDefaultsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("secret-session-token-4417", forKey: "sessionToken")
        defaults.set("free", forKey: "plan")
        let directory = FileManager.default.temporaryDirectory.appending(path: "UserDefaultsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [DebugDrawerUserDefaults.Command] = [
            .set(key: "sessionToken", value: .string("attacker")),
            .remove(key: "sessionToken"),
            .set(key: "DebugDrawer.UserDefaults.originalValues", value: .string("attacker")),
            .set(key: "Plan", value: .string("pro")),
            .set(key: "plan", value: .string("enterprise")),
            .set(key: "plan", value: .bool(true)),
            .set(key: "itemsPerPage", value: .integer(101)),
            .set(key: "itemsPerPage", value: .double(20)),
            .set(key: "discount", value: .double(0.75)),
            .set(key: "greeting", value: .string("Hello, everyone!")),
            .set(key: "plan", value: .string("pro")),
            .set(key: "itemsPerPage", value: .integer(10)),
            .set(key: "discount", value: .double(0.5))
        ]
        var payloads: [(String, Data)] = try [(sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60)))]
        payloads += try commands.map { try (defaultsID, TransportMessage.payload($0)) }
        payloads.append((defaultsID, Data(#"{"set":{"key":"plan"}}"#.utf8)))
        for (index, (id, payload)) in payloads.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: String(format: "%03d.json", index)))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let model = DebugDrawerUserDefaults(keys: allowlist, defaults: defaults)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.userDefaults(model))
        let expectedEvents: [DebugDrawerAuditEntry.Event] = [
            .commandRefused(.notExposed),
            .commandRefused(.notExposed),
            .commandRefused(.notExposed),
            .commandRefused(.notExposed),
            .commandRefused(.malformedCommand),
            .commandRefused(.malformedCommand),
            .commandRefused(.malformedCommand),
            .commandRefused(.malformedCommand),
            .commandRefused(.malformedCommand),
            .commandRefused(.malformedCommand),
            .commandApplied,
            .commandApplied,
            .commandApplied,
            .commandRefused(.malformedCommand)
        ]

        try sut.start()
        defer { sut.stop() }

        let actual = sessions.auditLog.filter { $0.capability == defaultsID }.map(\.event)
        #expect(actual == expectedEvents)
        #expect(defaults.string(forKey: "sessionToken") == "secret-session-token-4417")
        #expect(defaults.string(forKey: "Plan") == nil)
        #expect(defaults.string(forKey: "plan") == "pro")
        #expect(defaults.integer(forKey: "itemsPerPage") == 10)
        #expect(defaults.double(forKey: "discount") == 0.5)
        #expect(defaults.object(forKey: "greeting") == nil)
        #expect(model.snapshot.editedKeys == ["discount", "itemsPerPage", "plan"])
    }

    @Test("With the capability off, every UserDefaults command is refused, in an open session, and nothing is served or written")
    func offRefusesEverything() throws {
        let suite = "UserDefaultsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("free", forKey: "plan")
        let directory = FileManager.default.temporaryDirectory.appending(path: "UserDefaultsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [DebugDrawerUserDefaults.Command] = [.set(key: "plan", value: .string("pro")), .remove(key: "plan"), .revertAll]
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let gate = Gate()
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.featureFlagOverrides(EmptyFlagAdapter()))
        try sut.start()
        defer { sut.stop() }
        sessions.perform(.open(duration: 60))
        var outcomes: [DebugDrawerAuditEntry.Event] = []

        /// Leaves each command in the store, has the receiver perform it, and keeps its outcome.
        func send(_ name: String) throws {
            for (index, command) in commands.enumerated() {
                let document = try StoreDocument(TransportMessage(kind: .command, pluginID: defaultsID, payload: TransportMessage.payload(command)))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(name)-\(index).json"))
                sut.reevaluateGates()
                if let last = sessions.auditLog.last, last.capability == defaultsID {
                    outcomes.append(last.event)
                }
            }
        }
        // Never enabled.
        try send("never")
        // Enabled, then disabled.
        sut.enable(.userDefaults(DebugDrawerUserDefaults(keys: allowlist, defaults: defaults)))
        sut.disable(defaultsID)
        try send("disabled")
        // Enabled behind its gate, turned off.
        sut.enable(.userDefaults(DebugDrawerUserDefaults(keys: allowlist, defaults: defaults))) { gate.isOpen }
        gate.isOpen = false
        try send("gated")
        let expectedOutcomes: [DebugDrawerAuditEntry.Event] =
            Array(repeating: .commandRefused(.unknownCapability), count: 6) + Array(repeating: .commandRefused(.capabilityDisabled), count: 3)

        sut.reevaluateGates()

        #expect(outcomes == expectedOutcomes)
        #expect(sessions.snapshot.isActive)
        #expect(defaults.string(forKey: "plan") == "free")
        #expect(defaults.object(forKey: DebugDrawerUserDefaults.originalValuesDefaultsKey) == nil)
        #expect(!FileManager.default.fileExists(atPath: layout.snapshotFile(for: defaultsID).path))
        #expect(!sut.servedIDs.contains(defaultsID))
    }

    @Test("Each edit's audit entry carries the key with its value before and after, and the revert's what it put back")
    func auditsEachEdit() throws {
        let suite = "UserDefaultsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("free", forKey: "plan")
        let directory = FileManager.default.temporaryDirectory.appending(path: "UserDefaultsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let payloads: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (defaultsID, TransportMessage.payload(DebugDrawerUserDefaults.Command.set(key: "plan", value: .string("pro")))),
            (defaultsID, TransportMessage.payload(DebugDrawerUserDefaults.Command.set(key: "showsTips", value: .bool(true)))),
            (defaultsID, TransportMessage.payload(DebugDrawerUserDefaults.Command.set(key: "plan", value: .string("free")))),
            (defaultsID, TransportMessage.payload(DebugDrawerUserDefaults.Command.remove(key: "plan")))
        ]
        for (index, (id, payload)) in payloads.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.userDefaults(DebugDrawerUserDefaults(keys: allowlist, defaults: defaults)))
        try sut.start()
        defer { sut.stop() }
        let session = try #require(sessions.snapshot.session)
        let expected: [DebugDrawerAuditEntry] = [
            DebugDrawerAuditEntry(
                date: Self.now, sessionID: session.id, capability: defaultsID, event: .commandApplied,
                changes: [.init(key: "plan", oldValue: .string("free"), newValue: .string("pro"))]
            ),
            DebugDrawerAuditEntry(
                date: Self.now, sessionID: session.id, capability: defaultsID, event: .commandApplied,
                changes: [.init(key: "showsTips", oldValue: nil, newValue: .bool(true))]
            ),
            DebugDrawerAuditEntry(
                date: Self.now, sessionID: session.id, capability: defaultsID, event: .commandApplied,
                changes: [.init(key: "plan", oldValue: .string("pro"), newValue: .string("free"))]
            ),
            DebugDrawerAuditEntry(
                date: Self.now, sessionID: session.id, capability: defaultsID, event: .commandApplied,
                changes: [.init(key: "plan", oldValue: .string("free"), newValue: nil)]
            ),
            DebugDrawerAuditEntry(
                date: Self.now, sessionID: session.id, capability: defaultsID, event: .changeReverted,
                changes: [
                    .init(key: "plan", oldValue: nil, newValue: .string("free")),
                    .init(key: "showsTips", oldValue: .bool(true), newValue: nil)
                ]
            ),
            DebugDrawerAuditEntry(date: Self.now, sessionID: session.id, capability: sessionsID, event: .sessionEnded(.ended))
        ]

        sessions.end()

        // Every entry of the session after its opening.
        let actual = Array(sessions.auditLog.filter { $0.sessionID == session.id }.dropFirst())
        #expect(actual == expected)
        #expect(defaults.string(forKey: "plan") == "free")
        #expect(defaults.object(forKey: "showsTips") == nil)
        #expect(defaults.object(forKey: DebugDrawerUserDefaults.originalValuesDefaultsKey) == nil)
    }

    @Test("An audit entry with changes encodes them as JSON a forwarder reads, and decodes back")
    func auditChangesEncode() throws {
        let entry = DebugDrawerAuditEntry(
            date: Date(timeIntervalSinceReferenceDate: 0), sessionID: nil, capability: defaultsID, event: .commandApplied,
            changes: [.init(key: "plan", oldValue: .string("free"), newValue: .string("pro"))]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let expected = #"{"capability":"DebugDrawer.UserDefaults","#
            + #""changes":[{"key":"plan","newValue":{"string":"pro"},"oldValue":{"string":"free"}}],"#
            + #""date":0,"event":{"commandApplied":{}}}"#

        let data = try encoder.encode(entry)

        #expect(String(bytes: data, encoding: .utf8) == expected)
        #expect(try JSONDecoder().decode(DebugDrawerAuditEntry.self, from: data) == entry)
    }

    @Test("An audit entry without changes encodes as before, and one written before changes existed decodes")
    func auditEntryWithoutChangesIsUnchanged() throws {
        let entry = DebugDrawerAuditEntry(date: Date(timeIntervalSinceReferenceDate: 0), sessionID: nil, capability: flagsID, event: .commandApplied)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let expected = #"{"capability":"DebugDrawer.FeatureFlagOverrides","date":0,"event":{"commandApplied":{}}}"#
        let older = Data(#"{"capability":"MyApp.LogLevels","date":785000000,"event":{"commandRefused":{"_0":"notExposed"}}}"#.utf8)

        let data = try encoder.encode(entry)
        let decoded = try JSONDecoder().decode(DebugDrawerAuditEntry.self, from: older)

        #expect(String(bytes: data, encoding: .utf8) == expected)
        #expect(decoded.changes == nil)
        #expect(decoded.event == .commandRefused(.notExposed))
    }

    @Test("As the session expires, the timer firing, each edited key is put back, audited before sessionEnded(.expired)")
    func revertsAsSessionExpires() throws {
        let suite = "UserDefaultsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(20, forKey: "itemsPerPage")
        let directory = FileManager.default.temporaryDirectory.appending(path: "UserDefaultsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let payloads: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 3600))),
            (defaultsID, TransportMessage.payload(DebugDrawerUserDefaults.Command.set(key: "itemsPerPage", value: .integer(50))))
        ]
        for (index, (id, payload)) in payloads.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let clock = MovableClock(Self.now)
        let timer = ManualTimer()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: timer)
        let model = DebugDrawerUserDefaults(keys: allowlist, defaults: defaults)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.userDefaults(model))
        try sut.start()
        defer { sut.stop() }
        let duringSession = defaults.integer(forKey: "itemsPerPage")
        let expectedTail: [DebugDrawerAuditEntry.Event] = [.changeReverted, .sessionEnded(.expired)]

        clock.set(Self.now.addingTimeInterval(300))
        timer.fire()

        #expect(duringSession == 50)
        #expect(defaults.integer(forKey: "itemsPerPage") == 20)
        #expect(model.snapshot.editedKeys.isEmpty)
        #expect(!sessions.snapshot.isActive)
        #expect(Array(sessions.auditLog.suffix(2).map(\.event)) == expectedTail)
    }

    @Test("The capability's gate turning off puts the edits back at once while the session goes on; the receiver's ends the session")
    func revertsAtGateOff() throws {
        let suite = "UserDefaultsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "UserDefaultsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let capabilityGate = Gate()
        let receiverGate = Gate()
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions) { receiverGate.isOpen }
        sut.enable(.userDefaults(DebugDrawerUserDefaults(keys: allowlist, defaults: defaults))) { capabilityGate.isOpen }
        try sut.start()
        defer { sut.stop() }
        sessions.perform(.open(duration: 60))

        /// Leaves an edit turning tips on in the store and has the receiver perform it.
        func turnTipsOn(_ name: String) throws {
            let payload = try TransportMessage.payload(DebugDrawerUserDefaults.Command.set(key: "showsTips", value: .bool(true)))
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: defaultsID, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(name).json"))
            sut.reevaluateGates()
        }
        try turnTipsOn("0")
        let firstEdit = defaults.object(forKey: "showsTips") as? Bool
        capabilityGate.isOpen = false
        sut.reevaluateGates()
        let afterCapabilityGate = (defaults.object(forKey: "showsTips") as? Bool, sessions.snapshot.isActive)
        capabilityGate.isOpen = true
        try turnTipsOn("1")
        let secondEdit = defaults.object(forKey: "showsTips") as? Bool
        receiverGate.isOpen = false

        sut.reevaluateGates()

        #expect(firstEdit == true)
        #expect(afterCapabilityGate == (nil, true))
        #expect(secondEdit == true)
        #expect(defaults.object(forKey: "showsTips") == nil)
        #expect(!sessions.snapshot.isActive)
        #expect(sessions.auditLog.last?.event == .sessionEnded(.disabledByHost))
    }

    @Test("Edits a session left when the app was killed are put back as the next launch makes the capability, before any session")
    func editsLeftByKillAreRevertedAtLaunch() throws {
        let suite = "UserDefaultsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("free", forKey: "plan")
        let directory = FileManager.default.temporaryDirectory.appending(path: "UserDefaultsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let payloads: [Data] = try [
            TransportMessage.payload(DebugDrawerUserDefaults.Command.set(key: "plan", value: .string("pro"))),
            TransportMessage.payload(DebugDrawerUserDefaults.Command.set(key: "greeting", value: .string("Hi")))
        ]
        for (index, payload) in payloads.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: defaultsID, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let killedLaunch = DebugDrawerReceiver(directory: directory, sessions: sessions)
        killedLaunch.enable(.userDefaults(DebugDrawerUserDefaults(keys: allowlist, defaults: defaults)))
        sessions.perform(.open(duration: 60))
        try killedLaunch.start()
        // The app is killed with the session open: nothing ends it, so its revert never runs.
        killedLaunch.stop()
        let leftByKill = (defaults.string(forKey: "plan"), defaults.string(forKey: "greeting"))
        // The next launch: a new process, whose model finds the record the edits left.
        let model = DebugDrawerUserDefaults(keys: allowlist, defaults: defaults)
        let recordedAtLaunch = model.snapshot.editedKeys

        _ = DebugDrawerReceiverCapability.userDefaults(model)

        #expect(leftByKill == ("pro", "Hi"))
        #expect(recordedAtLaunch == ["greeting", "plan"])
        #expect(defaults.string(forKey: "plan") == "free")
        #expect(defaults.object(forKey: "greeting") == nil)
        #expect(model.snapshot.editedKeys.isEmpty)
        #expect(defaults.object(forKey: DebugDrawerUserDefaults.originalValuesDefaultsKey) == nil)
    }

    @Test("With the persistent scope edits outlive the session and the next launch, until a sidecar sends revertAll")
    func persistentEditsStay() throws {
        let suite = "UserDefaultsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "UserDefaultsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.userDefaults(DebugDrawerUserDefaults(keys: allowlist, defaults: defaults), scope: .persistent))
        try sut.start()
        defer { sut.stop() }

        /// Leaves `command` in the store and has the receiver perform it.
        func send(_ command: DebugDrawerUserDefaults.Command, _ name: String) throws {
            let document = try StoreDocument(TransportMessage(kind: .command, pluginID: defaultsID, payload: TransportMessage.payload(command)))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(name).json"))
            sut.reevaluateGates()
        }
        sessions.perform(.open(duration: 60))
        try send(.set(key: "showsTips", value: .bool(true)), "0")
        sessions.end()
        let afterSession = defaults.object(forKey: "showsTips") as? Bool
        let nextLaunch = DebugDrawerUserDefaults(keys: allowlist, defaults: defaults)
        _ = DebugDrawerReceiverCapability.userDefaults(nextLaunch, scope: .persistent)
        let afterLaunch = (defaults.object(forKey: "showsTips") as? Bool, nextLaunch.snapshot.editedKeys)
        sessions.perform(.open(duration: 60))

        try send(.revertAll, "1")

        #expect(afterSession == true)
        #expect(afterLaunch == (true, ["showsTips"]))
        #expect(defaults.object(forKey: "showsTips") == nil)
        #expect(sessions.auditLog.last?.changes == [.init(key: "showsTips", oldValue: .bool(true), newValue: nil)])
    }

    @Test("A key that read its registered default is removed by the revert, so the app follows the default again")
    func registeredDefaultIsRemovedByRevert() throws {
        let suite = "UserDefaultsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.register(defaults: ["itemsPerPage": 30])
        let model = DebugDrawerUserDefaults(keys: allowlist, defaults: defaults)
        model.perform(.set(key: "itemsPerPage", value: .integer(60)))
        let edited = defaults.integer(forKey: "itemsPerPage")
        defaults.register(defaults: ["itemsPerPage": 40])

        model.perform(.revertAll)

        #expect(edited == 60)
        #expect(defaults.persistentDomain(forName: suite)?["itemsPerPage"] == nil)
        #expect(defaults.integer(forKey: "itemsPerPage") == 40)
    }

    @Test("A value the app writes outside the receiver reaches the snapshot through UserDefaults' change notification")
    func followsTheAppsOwnWrites() async throws {
        let suite = "UserDefaultsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sut = DebugDrawerUserDefaults(keys: allowlist, defaults: defaults)
        let expected = DebugDrawerUserDefaultsValue.string("pro")

        defaults.set("pro", forKey: "plan")

        for await snapshot in sut.$snapshot.values where snapshot.entries.first?.value == expected {
            break
        }
        #expect(sut.snapshot.entries.first?.value == expected)
        #expect(sut.snapshot.editedKeys.isEmpty)
    }

    @Test("With a grant policy an edit needs a grant listing the capability; another's is capabilityNotGranted")
    func grantRequiredUnderPolicy() throws {
        let suite = "UserDefaultsReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "UserDefaultsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let serverKey = Curve25519.Signing.PrivateKey()
        let policy = DebugDrawerGrantPolicy(
            verifier: DebugDrawerSignedGrantVerifier(keys: [.ed25519(serverKey.publicKey)]), audience: "com.example.MyApp"
        )
        let sessions = DebugDrawerSessions(
            maximumDuration: 300, auditCapacity: 100, grantPolicy: policy, clock: MovableClock(Self.now), timer: ManualTimer()
        )
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.userDefaults(DebugDrawerUserDefaults(keys: allowlist, defaults: defaults)))
        sut.enable(.featureFlagOverrides(EmptyFlagAdapter()))
        try sut.start()
        defer { sut.stop() }
        let signer = DebugDrawerTestGrantSigner(key: serverKey)
        let flagsOnly = try signer.token(for: DebugDrawerGrant(
            id: "g-flags", subject: "jane@example.com", audiences: ["com.example.MyApp"], capabilities: [flagsID],
            notBefore: Self.now, expires: Self.now.addingTimeInterval(120)
        ))
        let userDefaults = try signer.token(for: DebugDrawerGrant(
            id: "g-defaults", subject: "jane@example.com", audiences: ["com.example.MyApp"], capabilities: [defaultsID],
            notBefore: Self.now, expires: Self.now.addingTimeInterval(120)
        ))
        var outcomes: [DebugDrawerAuditEntry.Event] = []

        /// Leaves an edit turning tips on in the store, has the receiver perform it, and keeps the
        /// last audit entry.
        func turnTipsOn(_ name: String) throws {
            let payload = try TransportMessage.payload(DebugDrawerUserDefaults.Command.set(key: "showsTips", value: .bool(true)))
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: defaultsID, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(name).json"))
            sut.reevaluateGates()
            if let last = sessions.auditLog.last {
                outcomes.append(last.event)
            }
        }
        sessions.perform(.open(duration: 60, grant: flagsOnly))
        try turnTipsOn("0")
        let withFlagsGrant = defaults.object(forKey: "showsTips")
        sessions.perform(.end)
        sessions.perform(.open(duration: 60, grant: userDefaults))
        try turnTipsOn("1")

        #expect(outcomes == [.commandRefused(.capabilityNotGranted), .commandApplied])
        #expect(withFlagsGrant == nil)
        #expect(defaults.object(forKey: "showsTips") as? Bool == true)
    }
}
