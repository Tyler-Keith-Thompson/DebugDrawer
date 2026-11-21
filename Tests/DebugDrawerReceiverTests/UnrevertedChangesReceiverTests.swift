@testable import DebugDrawerReceiver
import DebugDrawerTestSupport
import Foundation
import Testing

/// What the app keeps outside the process, as a tweak's stored value or a file: the same instance
/// is handed to the model of each launch, as each launch reads the same disk.
@MainActor
private final class FakeDisk {
    var value: Int?
    var resets = 0
}

/// A model of the app's own whose setting persists on the disk, and which keeps no record of what
/// a session changed: only the receiver's record can revert it after a kill.
@MainActor
private final class PersistedSettingModel: DebugDrawerPluginModel {
    struct Snapshot: Codable, Equatable, Sendable {
        var value: Int?
    }

    enum Command: Codable, Equatable, Sendable {
        case set(Int)
        case reset
    }

    let disk: FakeDisk
    private let willPerform: @MainActor (Command) -> Void
    @Published private(set) var snapshot: Snapshot

    init(disk: FakeDisk, willPerform: @escaping @MainActor (Command) -> Void = { _ in }) {
        self.disk = disk
        self.willPerform = willPerform
        snapshot = Snapshot(value: disk.value)
    }

    func perform(_ command: Command) {
        willPerform(command)
        switch command {
        case let .set(value):
            disk.value = value
        case .reset:
            disk.resets += 1
            disk.value = nil
        }
        snapshot = Snapshot(value: disk.value)
    }
}

/// The host's remote configuration for one capability's gate, which the test flips.
@MainActor
private final class FakeGate {
    var isOpen = true
}

/// A flag service that keeps its overrides across launches: the same instance serves each launch.
@MainActor
private final class FakeFlagAdapter: DebugDrawerFeatureFlagAdapter {
    private(set) var overrides: [String: DebugDrawerFeatureFlagValue] = [:]

    func overridableFlags() -> [DebugDrawerFeatureFlag] {
        [DebugDrawerFeatureFlag(key: "new-checkout", value: overrides["new-checkout"] ?? .bool(false))]
    }

    func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
        overrides[key] = value
    }

    func clearOverride(forKey key: String) {
        overrides[key] = nil
    }
}

// The receiver's record of the session-scoped changes it owes a revert (DD-267): a launch killed or
// quit during a session leaves its changes there, and the next launch reverts each as it enables
// the capability. A "launch" is a receiver and sessions of their own over one store directory,
// dropped with the session open (`stop()`, with no end), as a kill leaves them; what persists
// across launches is the store and the fake disk. Commands are files left in the store the way a
// sidecar's transport leaves them, performed as the receiver starts, so nothing is awaited.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct UnrevertedChangesReceiverTests {
    private let settingID = "App.Setting"
    private let sessionsID = DebugDrawerSessions.pluginID

    @Test("A session-scoped change a killed launch left is reverted as the next launch enables the capability, and audited in that session")
    func changeLeftByKillIsReverted() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "UnrevertedChangesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (settingID, TransportMessage.payload(PersistedSettingModel.Command.set(7)))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let disk = FakeDisk()
        let killedSessions = DebugDrawerSessions(maximumDuration: 300)
        let killedLaunch = DebugDrawerReceiver(directory: directory, sessions: killedSessions)
        killedLaunch.enable(.model(PersistedSettingModel(disk: disk), id: settingID, scope: .session(revertWith: .reset)))
        try killedLaunch.start()
        let killedSession = try #require(killedSessions.snapshot.session)
        killedLaunch.stop()
        let leftByKill = disk.value
        let record = killedLaunch.appDirectory.appending(path: UnrevertedChanges.fileName)
        let recordLeft = FileManager.default.fileExists(atPath: record.path)
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let expectedEvents: [DebugDrawerAuditEntry.Event] = [.changeReverted]

        sut.enable(.model(PersistedSettingModel(disk: disk), id: settingID, scope: .session(revertWith: .reset)))
        try sut.start()
        defer { sut.stop() }

        #expect(leftByKill == 7)
        #expect(recordLeft)
        #expect(disk.value == nil)
        #expect(disk.resets == 1)
        #expect(sessions.auditLog.map(\.event) == expectedEvents)
        #expect(sessions.auditLog.map(\.capability) == [settingID])
        #expect(sessions.auditLog.map(\.sessionID) == [killedSession.id])
        #expect(!FileManager.default.fileExists(atPath: record.path))
    }

    @Test("A session that ended leaves nothing to revert at the next launch: no second revert, no audit entry")
    func endedSessionLeavesNothing() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "UnrevertedChangesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (settingID, TransportMessage.payload(PersistedSettingModel.Command.set(7))),
            (settingID, TransportMessage.payload(PersistedSettingModel.Command.set(8))),
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.end))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let disk = FakeDisk()
        let firstLaunch = DebugDrawerReceiver(directory: directory, sessions: DebugDrawerSessions(maximumDuration: 300))
        firstLaunch.enable(.model(PersistedSettingModel(disk: disk), id: settingID, scope: .session(revertWith: .reset)))
        try firstLaunch.start()
        firstLaunch.stop()
        let resetsAtEnd = disk.resets
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)

        sut.enable(.model(PersistedSettingModel(disk: disk), id: settingID, scope: .session(revertWith: .reset)))
        try sut.start()
        defer { sut.stop() }

        #expect(resetsAtEnd == 1)
        #expect(disk.resets == 1)
        #expect(sessions.auditLog.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sut.appDirectory.appending(path: UnrevertedChanges.fileName).path))
    }

    @Test("The record names the capability before the model sees the change, so a kill in between leaves the revert owed")
    func recordWrittenBeforeChange() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "UnrevertedChangesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (settingID, TransportMessage.payload(PersistedSettingModel.Command.set(7)))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sut = DebugDrawerReceiver(directory: directory, sessions: DebugDrawerSessions(maximumDuration: 300))
        let record = sut.appDirectory.appending(path: UnrevertedChanges.fileName)
        var recordAsSet: String?
        let model = PersistedSettingModel(disk: FakeDisk()) { command in
            if command == .set(7) {
                recordAsSet = (try? Data(contentsOf: record)).flatMap { String(data: $0, encoding: .utf8) }
            }
        }
        sut.enable(.model(model, id: settingID, scope: .session(revertWith: .reset)))

        try sut.start()
        defer { sut.stop() }

        let actual = try #require(recordAsSet)
        #expect(actual.contains("\"capability\":\"\(settingID)\""))
    }

    @Test("A capability not enabled at the next launch keeps its record, and is reverted in the first launch that enables it")
    func recordKeptUntilEnabled() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "UnrevertedChangesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (settingID, TransportMessage.payload(PersistedSettingModel.Command.set(7)))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let disk = FakeDisk()
        let killedSessions = DebugDrawerSessions(maximumDuration: 300)
        let killedLaunch = DebugDrawerReceiver(directory: directory, sessions: killedSessions)
        killedLaunch.enable(.model(PersistedSettingModel(disk: disk), id: settingID, scope: .session(revertWith: .reset)))
        try killedLaunch.start()
        let killedSession = try #require(killedSessions.snapshot.session)
        killedLaunch.stop()
        let otherSessions = DebugDrawerSessions(maximumDuration: 300)
        let launchWithout = DebugDrawerReceiver(directory: directory, sessions: otherSessions)
        launchWithout.enable(.model(PersistedSettingModel(disk: FakeDisk()), id: "App.Other", scope: .session(revertWith: .reset)))
        try launchWithout.start()
        launchWithout.stop()
        let valueWithout = disk.value
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        try sut.start()
        defer { sut.stop() }

        sut.enable(.model(PersistedSettingModel(disk: disk), id: settingID, scope: .session(revertWith: .reset)))

        #expect(valueWithout == 7)
        #expect(otherSessions.auditLog.isEmpty)
        #expect(disk.value == nil)
        #expect(sessions.auditLog.map(\.event) == [.changeReverted])
        #expect(sessions.auditLog.map(\.sessionID) == [killedSession.id])
    }

    @Test("A command the capability refuses records nothing to revert at the next launch")
    func refusedCommandRecordsNothing() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "UnrevertedChangesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (settingID, Data(#"{"rename":{"to":"x"}}"#.utf8))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let disk = FakeDisk()
        let killedSessions = DebugDrawerSessions(maximumDuration: 300)
        let killedLaunch = DebugDrawerReceiver(directory: directory, sessions: killedSessions)
        killedLaunch.enable(.model(PersistedSettingModel(disk: disk), id: settingID, scope: .session(revertWith: .reset)))
        try killedLaunch.start()
        killedLaunch.stop()
        let refusals = killedSessions.auditLog.map(\.event).filter { $0 == .commandRefused(.malformedCommand) }
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)

        sut.enable(.model(PersistedSettingModel(disk: disk), id: settingID, scope: .session(revertWith: .reset)))
        try sut.start()
        defer { sut.stop() }

        #expect(refusals.count == 1)
        #expect(disk.resets == 0)
        #expect(sessions.auditLog.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: sut.appDirectory.appending(path: UnrevertedChanges.fileName).path))
    }

    @Test("A persistent capability's change records nothing: the next launch keeps it")
    func persistentChangeRecordsNothing() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "UnrevertedChangesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (settingID, TransportMessage.payload(PersistedSettingModel.Command.set(7)))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let disk = FakeDisk()
        let killedLaunch = DebugDrawerReceiver(directory: directory, sessions: DebugDrawerSessions(maximumDuration: 300))
        killedLaunch.enable(.model(PersistedSettingModel(disk: disk), id: settingID, scope: .persistent))
        try killedLaunch.start()
        let recordLeft = FileManager.default.fileExists(atPath: killedLaunch.appDirectory.appending(path: UnrevertedChanges.fileName).path)
        killedLaunch.stop()
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)

        sut.enable(.model(PersistedSettingModel(disk: disk), id: settingID, scope: .persistent))
        try sut.start()
        defer { sut.stop() }

        #expect(!recordLeft)
        #expect(disk.value == 7)
        #expect(sessions.auditLog.isEmpty)
    }

    @Test("A capability whose gate turns off is reverted at once and leaves nothing to revert at the next launch")
    func gateRevertClearsRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "UnrevertedChangesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (settingID, TransportMessage.payload(PersistedSettingModel.Command.set(7)))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let disk = FakeDisk()
        let gate = FakeGate()
        let killedLaunch = DebugDrawerReceiver(directory: directory, sessions: DebugDrawerSessions(maximumDuration: 300))
        killedLaunch.enable(.model(PersistedSettingModel(disk: disk), id: settingID, scope: .session(revertWith: .reset))) { gate.isOpen }
        try killedLaunch.start()
        gate.isOpen = false
        killedLaunch.reevaluateGates()
        killedLaunch.stop()
        let resetsByGate = disk.resets
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)

        sut.enable(.model(PersistedSettingModel(disk: disk), id: settingID, scope: .session(revertWith: .reset)))
        try sut.start()
        defer { sut.stop() }

        #expect(resetsByGate == 1)
        #expect(disk.resets == 1)
        #expect(sessions.auditLog.isEmpty)
    }

    @Test("Feature flag overrides keep their own record: after a kill the next launch clears them once, with no revert from the receiver")
    func flagsRevertOnce() throws {
        let suite = temporarySuiteName("UnrevertedChangesReceiverTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "UnrevertedChangesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let flagsID = DebugDrawerFeatureFlagOverrides.pluginID
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (flagsID, TransportMessage.payload(DebugDrawerFeatureFlagOverrides.Command.setOverride(key: "new-checkout", value: .bool(true))))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let adapter = FakeFlagAdapter()
        let killedLaunch = DebugDrawerReceiver(directory: directory, sessions: DebugDrawerSessions(maximumDuration: 300))
        killedLaunch.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: adapter, defaults: defaults)))
        try killedLaunch.start()
        let recordLeft = FileManager.default.fileExists(atPath: killedLaunch.appDirectory.appending(path: UnrevertedChanges.fileName).path)
        killedLaunch.stop()
        let leftByKill = adapter.overrides
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let expectedLeft: [String: DebugDrawerFeatureFlagValue] = ["new-checkout": .bool(true)]

        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: adapter, defaults: defaults)))
        try sut.start()
        defer { sut.stop() }

        #expect(leftByKill == expectedLeft)
        #expect(!recordLeft)
        #expect(adapter.overrides.isEmpty)
        #expect(sessions.auditLog.isEmpty)
    }
}
