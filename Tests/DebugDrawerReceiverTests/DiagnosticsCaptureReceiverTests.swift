@testable import DebugDrawerReceiver
import DebugDrawerTestSupport
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

/// The host's remote switch for the capability, which the test flips.
@MainActor
private final class RemoteSwitch {
    var isOn = true
}

/// A flag service with nothing to override, so a receiver serves a capability other than the
/// capture.
@MainActor
private final class EmptyFlagAdapter: DebugDrawerFeatureFlagAdapter {
    func overridableFlags() -> [DebugDrawerFeatureFlag] { [] }
    func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {}
    func clearOverride(forKey key: String) {}
}

// The diagnostics capture end to end through the receiver alone, as a release build links it: that
// nothing is captured or written outside a session and a sidecar's start (criterion 1), that what
// reaches the store is redacted (criterion 2; the bounds are DiagnosticsCaptureTests'), and that
// the capture is deleted from memory and the store as the sidecar stops it, as the session ends or
// expires, as a gate turns it off, and at the launch after a kill, while the copy a sidecar
// exported into its report stays (criterion 3). Commands are files left in the store the way a
// sidecar's transport leaves them; the receiver performs those waiting as it starts. Sessions run
// on a clock the test moves and a timer it fires. The store's file is read once the receiver's
// writer has written what the test waits for, watched with DirectoryWatcher, never by sleeping.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DiagnosticsCaptureReceiverTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let captureID = DebugDrawerDiagnosticsCapture.pluginID
    private let sessionsID = DebugDrawerSessions.pluginID

    @Test("Outside a session nothing is captured or written: log and record evaluate no argument, no URL protocol installed, nothing in the store")
    func nothingCapturedOutsideSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsCaptureReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.diagnosticsCapture(capture))
        let sessionsFile = layout.snapshotFile(for: sessionsID)
        let protocolsBefore = URLSessionConfiguration.default.protocolClasses?.map { ObjectIdentifier($0) }
        let request = URLRequest(url: URL(string: "https://api.example.com/orders")!)
        var evaluated = 0
        func evaluate(_ text: String) -> String {
            evaluated += 1
            return text
        }
        func evaluateRequest() -> URLRequest {
            evaluated += 1
            return request
        }
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        try sut.start()
        defer { sut.stop() }

        capture.log(level: .error, message: evaluate("checkout failed"), metadata: ["order": evaluate("1042")])
        capture.record(evaluateRequest(), body: Data(evaluate("{}").utf8), started: Self.now)

        if !FileManager.default.fileExists(atPath: sessionsFile.path) {
            for await _ in watcher.changes where FileManager.default.fileExists(atPath: sessionsFile.path) {
                break
            }
        }
        let files = try FileManager.default.subpathsOfDirectory(atPath: layout.snapshots.path).sorted()
        let expectedFiles = [sessionsFile.lastPathComponent]
        #expect(evaluated == 0)
        #expect(!capture.snapshot.isCapturing)
        #expect(capture.snapshot.lines.isEmpty)
        #expect(capture.snapshot.requests.isEmpty)
        #expect(files == expectedFiles)
        #expect(URLSessionConfiguration.default.protocolClasses?.map { ObjectIdentifier($0) } == protocolsBefore)
    }

    @Test("A session opened without the sidecar's start captures nothing; start outside a session is refused noActiveSession")
    func nothingCapturedWithoutStart() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsCaptureReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let start = try TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.start)
        try layout.write(
            StoreDocument(TransportMessage(kind: .command, pluginID: captureID, payload: start)).encoded(),
            to: layout.commands.appending(path: "0.json")
        )
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.diagnosticsCapture(capture))
        var evaluated = 0
        func evaluate(_ text: String) -> String {
            evaluated += 1
            return text
        }
        try sut.start()
        defer { sut.stop() }
        let refusal = sessions.auditLog.last
        let expectedRefusal = DebugDrawerAuditEntry(date: Self.now, sessionID: nil, capability: captureID, event: .commandRefused(.noActiveSession))

        sessions.perform(.open(duration: 60))
        capture.log(level: .info, message: evaluate("signed in"))

        #expect(refusal == expectedRefusal)
        #expect(evaluated == 0)
        #expect(!capture.snapshot.isCapturing)
        #expect(capture.snapshot.lines.isEmpty)
    }

    @Test("Made to require a grant, start in a session without one is refused grantMissing and nothing is captured")
    func startNeedsGrantWhenRequired() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsCaptureReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (captureID, TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.start))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.diagnosticsCapture(capture).requiringGrant())

        try sut.start()
        defer { sut.stop() }
        capture.log(level: .info, message: "signed in")

        #expect(sessions.auditLog.last?.event == .commandRefused(.grantMissing))
        #expect(!capture.snapshot.isCapturing)
        #expect(capture.snapshot.lines.isEmpty)
    }

    @Test("Until the host enables it, start is refused unknownCapability in an open session, and no capture file is written")
    func offUnlessEnabled() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsCaptureReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (captureID, TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.start))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: MovableClock(Self.now), timer: ManualTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let flagSuite = temporarySuiteName("DiagnosticsCaptureReceiverTests.flags")
        let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
        defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: EmptyFlagAdapter(), defaults: flagDefaults)))

        try sut.start()
        defer { sut.stop() }

        let session = try #require(sessions.snapshot.session)
        let expectedEntry = DebugDrawerAuditEntry(
            date: Self.now, sessionID: session.id, capability: captureID, event: .commandRefused(.unknownCapability)
        )
        #expect(sessions.auditLog.last == expectedEntry)
        #expect(!FileManager.default.fileExists(atPath: layout.snapshotFile(for: captureID).path))
    }

    @Test("Once started in a session, a line and a request reach the store's snapshot redacted: no secret is in the file")
    func capturedEntriesReachStoreRedacted() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsCaptureReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (captureID, TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.start))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.diagnosticsCapture(capture))
        let snapshotFile = layout.snapshotFile(for: captureID)
        var request = URLRequest(url: URL(string: "https://api.example.com/orders?token=q-secret-1&page=2")!)
        request.httpMethod = "POST"
        request.setValue("Bearer h-secret-2", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(#"{"password":"b-secret-3","item":"tea"}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: 201, httpVersion: "HTTP/1.1",
            headerFields: ["Set-Cookie": "sid=c-secret-4", "Content-Type": "application/json"]
        )
        let responseBody = Data(#"{"customer":"jane@example.com","id":7}"#.utf8)
        let secrets = ["q-secret-1", "h-secret-2", "b-secret-3", "c-secret-4", "jane@example.com", "l-secret-5", "m-secret-6"]
        let expectedLine = DebugDrawerDiagnosticsCapture.LogLine(
            id: 1, timestamp: Self.now, level: .notice, message: "Signed in [REDACTED] with [REDACTED]",
            metadata: ["password": "[REDACTED]", "screen": "checkout"], subsystem: "com.example.shop", category: "auth"
        )
        let expectedRequest = DebugDrawerDiagnosticsCapture.Request(
            id: 2, started: Self.now, finished: Self.now, method: "POST", url: "https://api.example.com/orders?token=[REDACTED]&page=2",
            requestHeaders: ["Authorization": "[REDACTED]", "Content-Type": "application/json"],
            requestBody: .json(#"{"item":"tea","password":"[REDACTED]"}"#),
            statusCode: 201, responseHeaders: ["Set-Cookie": "[REDACTED]", "Content-Type": "application/json"],
            responseBody: .json(#"{"customer":"[REDACTED]","id":7}"#), failure: nil
        )
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        try sut.start()
        defer { sut.stop() }

        capture.log(
            level: .notice, message: "Signed in jane@example.com with password=l-secret-5",
            metadata: ["password": "m-secret-6", "screen": "checkout"], subsystem: "com.example.shop", category: "auth"
        )
        capture.record(request, response: response, body: responseBody, started: Self.now)

        func stored() -> (snapshot: DebugDrawerDiagnosticsCapture.Snapshot, text: String)? {
            guard let data = try? Data(contentsOf: snapshotFile), let document = StoreDocument.decoded(from: data),
                  let snapshot = try? JSONDecoder().decode(DebugDrawerDiagnosticsCapture.Snapshot.self, from: document.message.payload),
                  let text = String(bytes: document.message.payload, encoding: .utf8)
            else { return nil }
            return (snapshot, text)
        }
        var actual = stored()
        if actual?.snapshot.requests.isEmpty != false {
            for await _ in watcher.changes {
                actual = stored()
                if actual?.snapshot.requests.isEmpty == false { break }
            }
        }
        let snapshot = try #require(actual?.snapshot)
        let text = try #require(actual?.text)
        #expect(snapshot.lines == [expectedLine])
        #expect(snapshot.requests == [expectedRequest])
        for secret in secrets {
            #expect(!text.contains(secret), "The store's file holds \(secret)")
        }
    }

    @Test("As the session ends, the capture is deleted from memory and the store, audited changeReverted")
    func deletedAtSessionEnd() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsCaptureReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (captureID, TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.start))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.diagnosticsCapture(capture))
        let snapshotFile = layout.snapshotFile(for: captureID)
        let marker = "order-7f3a-marker"
        func storedText() -> String? {
            guard let data = try? Data(contentsOf: snapshotFile), let document = StoreDocument.decoded(from: data) else { return nil }
            return String(bytes: document.message.payload, encoding: .utf8)
        }
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        try sut.start()
        defer { sut.stop() }
        capture.log(level: .info, message: "Placed \(marker)")
        if storedText()?.contains(marker) != true {
            for await _ in watcher.changes where storedText()?.contains(marker) == true {
                break
            }
        }
        let expectedTail: [DebugDrawerAuditEntry.Event] = [.changeReverted, .sessionEnded(.ended)]

        sessions.end()

        let afterEnd = storedText()
        #expect(!capture.snapshot.isCapturing)
        #expect(capture.snapshot.lines.isEmpty)
        #expect(afterEnd?.contains(marker) != true)
        #expect(Array(sessions.auditLog.suffix(2).map(\.event)) == expectedTail)
    }

    @Test("As the session expires, the timer firing, the capture is deleted from memory and the store")
    func deletedAtExpiry() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsCaptureReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (captureID, TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.start))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let clock = MovableClock(Self.now)
        let timer = ManualTimer()
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: timer)
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.diagnosticsCapture(capture))
        let snapshotFile = layout.snapshotFile(for: captureID)
        let marker = "order-9c1e-marker"
        func storedText() -> String? {
            guard let data = try? Data(contentsOf: snapshotFile), let document = StoreDocument.decoded(from: data) else { return nil }
            return String(bytes: document.message.payload, encoding: .utf8)
        }
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        try sut.start()
        defer { sut.stop() }
        capture.log(level: .info, message: "Placed \(marker)")
        if storedText()?.contains(marker) != true {
            for await _ in watcher.changes where storedText()?.contains(marker) == true {
                break
            }
        }
        let expectedTail: [DebugDrawerAuditEntry.Event] = [.changeReverted, .sessionEnded(.expired)]

        clock.set(Self.now.addingTimeInterval(60))
        timer.fire()

        #expect(!capture.snapshot.isCapturing)
        #expect(capture.snapshot.lines.isEmpty)
        #expect(storedText()?.contains(marker) != true)
        #expect(Array(sessions.auditLog.suffix(2).map(\.event)) == expectedTail)
    }

    @Test("An expiry the timer missed (a suspended app): what arrives after it is dropped, and the next command deletes the capture")
    func expiryFoundLate() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsCaptureReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (captureID, TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.start))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.diagnosticsCapture(capture))
        try sut.start()
        defer { sut.stop() }
        clock.set(Self.now.addingTimeInterval(61))
        capture.log(level: .info, message: "after the expiry")
        let export = try TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.export)
        try layout.write(
            StoreDocument(TransportMessage(kind: .command, pluginID: captureID, payload: export)).encoded(),
            to: layout.commands.appending(path: "2.json")
        )
        let expectedTail: [DebugDrawerAuditEntry.Event] = [.changeReverted, .sessionEnded(.expired), .commandRefused(.noActiveSession)]

        sut.reevaluateGates()

        #expect(!capture.snapshot.isCapturing)
        #expect(capture.snapshot.lines.isEmpty)
        #expect(Array(sessions.auditLog.suffix(3).map(\.event)) == expectedTail)
    }

    @Test("The capability's gate turned off deletes the capture and its file at once, audited changeReverted, while the session goes on")
    func deletedWhenGateTurnsOff() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsCaptureReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (captureID, TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.start))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let gate = RemoteSwitch()
        sut.enable(.diagnosticsCapture(capture)) { gate.isOn }
        let snapshotFile = layout.snapshotFile(for: captureID)
        let marker = "order-51d0-marker"
        func storedText() -> String? {
            guard let data = try? Data(contentsOf: snapshotFile), let document = StoreDocument.decoded(from: data) else { return nil }
            return String(bytes: document.message.payload, encoding: .utf8)
        }
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        try sut.start()
        defer { sut.stop() }
        capture.log(level: .info, message: "Placed \(marker)")
        if storedText()?.contains(marker) != true {
            for await _ in watcher.changes where storedText()?.contains(marker) == true {
                break
            }
        }

        gate.isOn = false
        sut.reevaluateGates()

        #expect(!capture.snapshot.isCapturing)
        #expect(capture.snapshot.lines.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: snapshotFile.path))
        #expect(sessions.snapshot.isActive)
        #expect(sessions.auditLog.last?.event == .changeReverted)
    }

    @Test("A capture left in the store by a launch killed during its session is deleted as the next launch enables the capability")
    func deletedAtNextLaunchAfterKill() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsCaptureReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (captureID, TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.start))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let clock = MovableClock(Self.now)
        let killedSessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let killedCapture = DebugDrawerDiagnosticsCapture(sessions: killedSessions, redaction: .standard, limits: .standard) { clock.now }
        let killedLaunch = DebugDrawerReceiver(directory: directory, sessions: killedSessions)
        killedLaunch.enable(.diagnosticsCapture(killedCapture))
        let snapshotFile = layout.snapshotFile(for: captureID)
        let marker = "order-c0de-marker"
        func storedText() -> String? {
            guard let data = try? Data(contentsOf: snapshotFile), let document = StoreDocument.decoded(from: data) else { return nil }
            return String(bytes: document.message.payload, encoding: .utf8)
        }
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        try killedLaunch.start()
        killedCapture.log(level: .info, message: "Placed \(marker)")
        if storedText()?.contains(marker) != true {
            for await _ in watcher.changes where storedText()?.contains(marker) == true {
                break
            }
        }
        // The app is killed with the session open: nothing ends it, so its revert never runs, and
        // the file stays as it was, where stop() would remove it.
        let leftover = try Data(contentsOf: snapshotFile)
        killedLaunch.stop()
        try layout.write(leftover, to: snapshotFile)
        let leftByKill = storedText()?.contains(marker) == true
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)

        sut.enable(.diagnosticsCapture(capture))

        #expect(leftByKill)
        #expect(!FileManager.default.fileExists(atPath: snapshotFile.path))
    }

    @Test("The sidecar's stop deletes the capture from memory and the store, audited commandApplied; the session goes on")
    func stopDeletes() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsCaptureReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (captureID, TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.start))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.diagnosticsCapture(capture))
        let snapshotFile = layout.snapshotFile(for: captureID)
        let marker = "order-ab12-marker"
        func storedText() -> String? {
            guard let data = try? Data(contentsOf: snapshotFile), let document = StoreDocument.decoded(from: data) else { return nil }
            return String(bytes: document.message.payload, encoding: .utf8)
        }
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        try sut.start()
        defer { sut.stop() }
        capture.log(level: .info, message: "Placed \(marker)")
        if storedText()?.contains(marker) != true {
            for await _ in watcher.changes where storedText()?.contains(marker) == true {
                break
            }
        }
        let stop = try TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.stop)
        try layout.write(
            StoreDocument(TransportMessage(kind: .command, pluginID: captureID, payload: stop)).encoded(),
            to: layout.commands.appending(path: "2.json")
        )

        sut.reevaluateGates()

        #expect(!capture.snapshot.isCapturing)
        #expect(capture.snapshot.lines.isEmpty)
        #expect(storedText()?.contains(marker) != true)
        #expect(sessions.snapshot.isActive)
        #expect(sessions.auditLog.last?.event == .commandApplied)
    }

    @Test("Export is recorded with what the capture held and audited; the sidecar's report copy keeps it while the app's copy goes with the session")
    func exportedCopyOutlivesSession() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "DiagnosticsCaptureReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (captureID, TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.start))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.diagnosticsCapture(capture))
        let snapshotFile = layout.snapshotFile(for: captureID)
        let marker = "order-e5e5-marker"
        func stored() -> DebugDrawerDiagnosticsCapture.Snapshot? {
            guard let data = try? Data(contentsOf: snapshotFile), let document = StoreDocument.decoded(from: data) else { return nil }
            return try? JSONDecoder().decode(DebugDrawerDiagnosticsCapture.Snapshot.self, from: document.message.payload)
        }
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        try sut.start()
        defer { sut.stop() }
        capture.log(level: .info, message: "Placed \(marker)", subsystem: "com.example.shop")
        if stored()?.lines.isEmpty != false {
            for await _ in watcher.changes where stored()?.lines.isEmpty == false {
                break
            }
        }
        // The sidecar copies what it read into its report, then tells the app it exported it.
        let report = try #require(stored())
        let export = try TransportMessage.payload(DebugDrawerDiagnosticsCapture.Command.export)
        try layout.write(
            StoreDocument(TransportMessage(kind: .command, pluginID: captureID, payload: export)).encoded(),
            to: layout.commands.appending(path: "2.json")
        )
        sut.reevaluateGates()
        let exports = capture.snapshot.exports
        let exportAudit = sessions.auditLog.last
        let expectedExports = [DebugDrawerDiagnosticsCapture.Export(date: Self.now, lines: 1, requests: 0)]
        let expectedConsole = "2026-05-09T06:13:20Z [info] com.example.shop: Placed \(marker)"

        sessions.end()

        #expect(exports == expectedExports)
        #expect(exportAudit?.capability == captureID)
        #expect(exportAudit?.event == .commandApplied)
        #expect(report.consoleLog == expectedConsole)
        #expect(capture.snapshot.lines.isEmpty)
        #expect(capture.snapshot.exports.isEmpty)
        #expect(stored()?.lines.isEmpty != false)
    }
}
