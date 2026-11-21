@testable import DebugDrawerReceiver
import Foundation
import Testing

/// A capability of the host's own whose snapshot holds a value no other app of the group should
/// read outside a session.
@MainActor
private final class SecretModel: DebugDrawerPluginModel {
    struct Snapshot: Codable, Equatable, Sendable {
        var value: String
    }

    enum Command: Codable, Equatable, Sendable {
        case set(String)
    }

    @Published private(set) var snapshot: Snapshot

    init(_ value: String) {
        snapshot = Snapshot(value: value)
    }

    func perform(_ command: Command) {
        switch command {
        case let .set(value): snapshot.value = value
        }
    }
}

/// A wall clock that stands still.
private struct FixedClock: SessionClock {
    let now: Date
}

/// A session timer that fires when the test says, as the system's would at the expiry.
@MainActor
private final class ManualTimer: SessionTimer {
    private var pending: (@MainActor () -> Void)?

    func schedule(at date: Date, _ fire: @escaping @MainActor () -> Void) {
        pending = fire
    }

    func cancel() {
        pending = nil
    }

    func fire() {
        let fire = pending
        cancel()
        fire?()
    }
}

/// A verifier that admits every token as a grant listing the capabilities the token names,
/// comma-separated: the tests choose what a grant lists without signing one.
private struct ListingVerifier: DebugDrawerGrantVerifier {
    let now: Date

    func verify(_ token: String) throws(DebugDrawerGrantVerificationError) -> DebugDrawerGrant {
        DebugDrawerGrant(
            id: UUID().uuidString, subject: "tester@example.com", audiences: ["com.example.MyApp"],
            capabilities: token.split(separator: ",").map(String.init), notBefore: now.addingTimeInterval(-60), expires: now.addingTimeInterval(3600)
        )
    }
}

/// The host's gate, as its remote configuration would flip it.
@MainActor
private final class HostGate {
    var isOn = true
}

// A capability's snapshot is served only within a session (DD-271): any app of the group can read
// the store, so outside a session it holds the app's presence file and the sessions' snapshot,
// nothing a capability holds; under a grant policy, or for a capability that requires a grant, a
// session reads only what its grant lists. Each test checks the files themselves, as another app
// of the group would read them. Snapshots are written as a session opens, before the call
// returns, and removed as it ends, so most tests assert with nothing to wait for; only the
// sessions' own snapshot is written on a later main-actor turn.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ReceiverSessionServingTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let sessionsID = DebugDrawerSessions.pluginID

    @Test("With no session open, the store holds the presence file and the sessions' snapshot, and no capability's snapshot")
    func nothingServedOutsideSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverSessionServingTests-\(UUID().uuidString)")
        let sut = DebugDrawerReceiver(directory: directory, sessions: DebugDrawerSessions(maximumDuration: 300))
        sut.enable(.model(SecretModel("flag-value-c0de"), id: "MyApp.Flags", scope: .persistent))
        sut.enable(.model(SecretModel("environment-c0de"), id: "MyApp.Environment", scope: .persistent))
        let layout = AppGroupStoreLayout(directory: sut.appDirectory)
        #expect(layout.create())
        let sessionsFile = layout.snapshotFile(for: sessionsID)
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        let expectedFiles = ["commands", "presence.json", "snapshots", "snapshots/\(sessionsFile.lastPathComponent)"]

        try sut.start()
        defer { sut.stop() }
        if !FileManager.default.fileExists(atPath: sessionsFile.path) {
            for await _ in watcher.changes where FileManager.default.fileExists(atPath: sessionsFile.path) {
                break
            }
        }

        let actualFiles = try FileManager.default.subpathsOfDirectory(atPath: sut.appDirectory.path).sorted()
        let everything = try actualFiles.compactMap { path -> Data? in
            var isDirectory: ObjCBool = false
            let file = sut.appDirectory.appending(path: path)
            guard FileManager.default.fileExists(atPath: file.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return nil }
            return try Data(contentsOf: file)
        }
        #expect(actualFiles == expectedFiles)
        #expect(!everything.contains { $0.range(of: Data("c0de".utf8)) != nil })
    }

    @Test("A capability's snapshot is in the store as soon as a session opens, and leaves it as the session ends or expires")
    func servedForTheSession() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverSessionServingTests-\(UUID().uuidString)")
        let timer = ManualTimer()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: timer)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let model = SecretModel("flag-value")
        sut.enable(.model(model, id: "MyApp.Flags", scope: .persistent))
        try sut.start()
        defer { sut.stop() }
        let file = AppGroupStoreLayout(directory: sut.appDirectory).snapshotFile(for: "MyApp.Flags")
        let expected = SecretModel.Snapshot(value: "flag-value")

        sessions.perform(.open(duration: 60))
        let servedWhileOpen = try JSONDecoder().decode(
            SecretModel.Snapshot.self, from: #require(StoreDocument.decoded(from: Data(contentsOf: file))).message.payload
        )
        sessions.end()
        let servedAfterEnd = FileManager.default.fileExists(atPath: file.path)
        sessions.perform(.open(duration: 60))
        let servedInSecondSession = FileManager.default.fileExists(atPath: file.path)
        timer.fire()
        let servedAfterExpiry = FileManager.default.fileExists(atPath: file.path)

        #expect(servedWhileOpen == expected)
        #expect(!servedAfterEnd)
        #expect(servedInSecondSession)
        #expect(!servedAfterExpiry)
    }

    @Test("A change in the session reaches the store; one the session's revert makes as it ends is never written after the file left")
    func revertAtEndIsNotWritten() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverSessionServingTests-\(UUID().uuidString)")
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: ManualTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let model = SecretModel("info")
        sut.enable(.model(model, id: "MyApp.LogLevel", scope: .session(revertWith: .set("info"))))
        try sut.start()
        defer { sut.stop() }
        let layout = AppGroupStoreLayout(directory: sut.appDirectory)
        let file = layout.snapshotFile(for: "MyApp.LogLevel")
        func stored() -> SecretModel.Snapshot? {
            guard let data = try? Data(contentsOf: file), let document = StoreDocument.decoded(from: data) else { return nil }
            return try? JSONDecoder().decode(SecretModel.Snapshot.self, from: document.message.payload)
        }
        let sessionsFile = layout.snapshotFile(for: sessionsID)
        func sessionsStored() -> DebugDrawerSessionState? {
            guard let data = try? Data(contentsOf: sessionsFile), let document = StoreDocument.decoded(from: data) else { return nil }
            return try? JSONDecoder().decode(DebugDrawerSessionState.self, from: document.message.payload)
        }
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        sessions.perform(.open(duration: 60))
        let command = try TransportMessage.payload(SecretModel.Command.set("debug"))
        try layout.write(
            StoreDocument(TransportMessage(kind: .command, pluginID: "MyApp.LogLevel", payload: command)).encoded(),
            to: layout.commands.appending(path: "0.json")
        )
        sut.reevaluateGates()
        if stored()?.value != "debug" {
            for await _ in watcher.changes where stored()?.value == "debug" {
                break
            }
        }

        sessions.end()
        // The sessions' snapshot saying the session ended is written on a later main-actor turn
        // than the revert's change would be, so once it is in the store any late write is too.
        if sessionsStored()?.isActive != false {
            for await _ in watcher.changes where sessionsStored()?.isActive == false {
                break
            }
        }

        #expect(model.snapshot.value == "info")
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("Under a grant policy a session reads only the snapshots of the capabilities its grant lists")
    func grantListsWhatIsServed() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverSessionServingTests-\(UUID().uuidString)")
        let policy = DebugDrawerGrantPolicy(verifier: ListingVerifier(now: Self.now), audience: "com.example.MyApp")
        let sessions = DebugDrawerSessions(
            maximumDuration: 300, auditCapacity: 100, grantPolicy: policy, clock: FixedClock(now: Self.now), timer: ManualTimer()
        )
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.model(SecretModel("flags"), id: "MyApp.Flags", scope: .persistent))
        sut.enable(.model(SecretModel("environment"), id: "MyApp.Environment", scope: .persistent))
        try sut.start()
        defer { sut.stop() }
        let layout = AppGroupStoreLayout(directory: sut.appDirectory)
        func servedCapabilities() -> [String] {
            ["MyApp.Environment", "MyApp.Flags"].filter { FileManager.default.fileExists(atPath: layout.snapshotFile(for: $0).path) }
        }
        let expectedFirst = ["MyApp.Flags"]
        let expectedSecond = ["MyApp.Environment", "MyApp.Flags"]

        sessions.perform(.open(duration: 60, grant: "MyApp.Flags"))
        let actualFirst = servedCapabilities()
        sessions.end()
        let actualBetween = servedCapabilities()
        sessions.perform(.open(duration: 60, grant: "MyApp.Flags,MyApp.Environment"))
        let actualSecond = servedCapabilities()
        sessions.end()
        sessions.perform(.open(duration: 60, grant: ""))
        let actualUnlisted = servedCapabilities()

        #expect(actualFirst == expectedFirst)
        #expect(actualBetween.isEmpty)
        #expect(actualSecond == expectedSecond)
        #expect(actualUnlisted.isEmpty)
    }

    @Test("Without a grant policy, a capability made to require a grant serves nothing to a session, while the others are served")
    func requiringGrantServesNothingWithoutGrant() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverSessionServingTests-\(UUID().uuidString)")
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: ManualTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.model(SecretModel("37.33,-122.03"), id: "MyApp.Location", scope: .persistent).requiringGrant())
        sut.enable(.model(SecretModel("flags"), id: "MyApp.Flags", scope: .persistent))
        try sut.start()
        defer { sut.stop() }
        let layout = AppGroupStoreLayout(directory: sut.appDirectory)

        sessions.perform(.open(duration: 60))

        #expect(!FileManager.default.fileExists(atPath: layout.snapshotFile(for: "MyApp.Location").path))
        #expect(FileManager.default.fileExists(atPath: layout.snapshotFile(for: "MyApp.Flags").path))
    }

    @Test("Under a grant policy, a capability made to require a grant is served to a session whose grant lists it")
    func requiringGrantServedWithGrant() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverSessionServingTests-\(UUID().uuidString)")
        let policy = DebugDrawerGrantPolicy(verifier: ListingVerifier(now: Self.now), audience: "com.example.MyApp")
        let sessions = DebugDrawerSessions(
            maximumDuration: 300, auditCapacity: 100, grantPolicy: policy, clock: FixedClock(now: Self.now), timer: ManualTimer()
        )
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.model(SecretModel("37.33,-122.03"), id: "MyApp.Location", scope: .persistent).requiringGrant())
        try sut.start()
        defer { sut.stop() }
        let file = AppGroupStoreLayout(directory: sut.appDirectory).snapshotFile(for: "MyApp.Location")

        sessions.perform(.open(duration: 60, grant: "MyApp.Location"))

        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test("In a session, the receiver's gate or the capability's turned off removes the snapshot; turned back on, it is served again")
    func gatesRemoveSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverSessionServingTests-\(UUID().uuidString)")
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: ManualTimer())
        let hostGate = HostGate()
        let capabilityGate = HostGate()
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions) { hostGate.isOn }
        sut.enable(.model(SecretModel("flags"), id: "MyApp.Flags", scope: .persistent)) { capabilityGate.isOn }
        try sut.start()
        defer { sut.stop() }
        let file = AppGroupStoreLayout(directory: sut.appDirectory).snapshotFile(for: "MyApp.Flags")
        sessions.perform(.open(duration: 60))
        let servedAtOpen = FileManager.default.fileExists(atPath: file.path)

        capabilityGate.isOn = false
        sut.reevaluateGates()
        let servedCapabilityOff = FileManager.default.fileExists(atPath: file.path)
        capabilityGate.isOn = true
        sut.reevaluateGates()
        let servedCapabilityBackOn = FileManager.default.fileExists(atPath: file.path)
        hostGate.isOn = false
        sut.reevaluateGates()
        let servedReceiverOff = FileManager.default.fileExists(atPath: file.path)
        hostGate.isOn = true
        sut.reevaluateGates()
        let servedReceiverBackOnNoSession = FileManager.default.fileExists(atPath: file.path)

        #expect(servedAtOpen)
        #expect(!servedCapabilityOff)
        #expect(servedCapabilityBackOn)
        #expect(!servedReceiverOff)
        // The receiver's gate ended the session, so nothing is served until another opens.
        #expect(!sessions.snapshot.isActive)
        #expect(!servedReceiverBackOnNoSession)
    }

    @Test("Starting removes, before anything else, every capability snapshot a launch killed during its session left")
    func leftoverSnapshotsRemovedAtStart() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverSessionServingTests-\(UUID().uuidString)")
        let sut = DebugDrawerReceiver(directory: directory, sessions: DebugDrawerSessions(maximumDuration: 300))
        sut.enable(.model(SecretModel("flags"), id: "MyApp.Flags", scope: .persistent))
        let layout = AppGroupStoreLayout(directory: sut.appDirectory)
        #expect(layout.create())
        let leftover = try StoreDocument(TransportMessage(
            kind: .snapshot, pluginID: "MyApp.Flags", payload: TransportMessage.payload(SecretModel.Snapshot(value: "killed launch's value"))
        )).encoded()
        try layout.write(leftover, to: layout.snapshotFile(for: "MyApp.Flags"))
        try layout.write(leftover, to: layout.snapshotFile(for: "MyApp.NoLongerEnabled"))

        try sut.start()
        defer { sut.stop() }

        #expect(layout.messageFiles(in: layout.snapshots).isEmpty)
    }

    @Test("Stopping removes the capabilities' snapshots from the store, the session still open")
    func stopRemovesSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverSessionServingTests-\(UUID().uuidString)")
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: ManualTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.model(SecretModel("flags"), id: "MyApp.Flags", scope: .persistent))
        try sut.start()
        let file = AppGroupStoreLayout(directory: sut.appDirectory).snapshotFile(for: "MyApp.Flags")
        sessions.perform(.open(duration: 60))
        let servedBeforeStop = FileManager.default.fileExists(atPath: file.path)

        sut.stop()

        #expect(servedBeforeStop)
        #expect(sessions.snapshot.isActive)
        #expect(!FileManager.default.fileExists(atPath: file.path))
    }

    @Test("A session open before the receiver starts is served as it starts")
    func sessionOpenBeforeStart() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ReceiverSessionServingTests-\(UUID().uuidString)")
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: ManualTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.model(SecretModel("flags"), id: "MyApp.Flags", scope: .persistent))
        sessions.perform(.open(duration: 60))

        try sut.start()
        defer { sut.stop() }

        #expect(FileManager.default.fileExists(atPath: AppGroupStoreLayout(directory: sut.appDirectory).snapshotFile(for: "MyApp.Flags").path))
    }
}
