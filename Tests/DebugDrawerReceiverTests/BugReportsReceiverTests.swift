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

/// Stands in for the key window: hands back the PNG bytes the test chose, and counts the drawings.
@MainActor
private final class FakeWindow {
    var drawings = 0
    var maximumBytesAsked: Int?
    let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])

    func draw(maximumBytes: Int) -> DebugDrawerBugReports.Screenshot {
        drawings += 1
        maximumBytesAsked = maximumBytes
        return .png(png)
    }
}

/// The app's state as the host chose to show it in a report.
private struct CartState: Encodable {
    struct Customer: Encodable {
        let email: String
        let plan: String
    }

    let screen: String
    let cartItems: Int
    let customer: Customer
}

/// The host's remote switch for the capability, which the test flips.
@MainActor
private final class RemoteSwitch {
    var isOn = true
}

/// Sees every request `URLSession.shared` and the URL loading system would send, and declines it,
/// so it changes nothing.
private final class RequestSpy: URLProtocol, @unchecked Sendable {
    static let seen = OSAllocatedUnfairLock(initialState: [URL?]())

    override static func canInit(with request: URLRequest) -> Bool {
        seen.withLock { $0.append(request.url) }
        return false
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {}
    override func stopLoading() {}
}

// Bug reports end to end through the receiver alone, as a release build links it: that a report
// exists only once the host's own trigger fires, within a session, and reaches the store where the
// sidecar reads it (criterion 1); that it holds the screenshot, the diagnostics capture's recent
// lines and the host's state, redacted (criterion 2); and that nothing the flow does sends a
// request (criterion 3; the receiver's module also depends on nothing, so it can't link the
// drawer's uploader, which modules.py asserts). Commands are files left in the store the way a
// sidecar's transport leaves them; the receiver performs those waiting as it starts. The store's
// file is read once the receiver's writer has written what the test waits for, watched with
// DirectoryWatcher, never by sleeping.
@MainActor
@Suite(.timeLimit(.minutes(1)), .serialized)
struct BugReportsReceiverTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let reportsID = DebugDrawerBugReports.pluginID
    private let captureID = DebugDrawerDiagnosticsCapture.pluginID
    private let sessionsID = DebugDrawerSessions.pluginID

    @Test("With no trigger called, an open session and the enabled capability make no report, in the store or the audit log")
    func nothingFiresWithoutTrigger() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BugReportsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let open = try TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))
        let command = StoreDocument(TransportMessage(kind: .command, pluginID: sessionsID, payload: open))
        try layout.write(command.encoded(), to: layout.commands.appending(path: "0.json"))
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let window = FakeWindow()
        var stateRead = 0
        let reports = DebugDrawerBugReports(
            sessions: sessions, diagnostics: nil, redaction: .standard, limits: .standard,
            state: {
                stateRead += 1
                return ["screen": "checkout"]
            },
            screenshot: window.draw(maximumBytes:),
            now: { clock.now }
        )
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.bugReports(reports))
        let snapshotFile = layout.snapshotFile(for: reportsID)
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
        let actual = try JSONDecoder().decode(DebugDrawerBugReports.Snapshot.self, from: document.message.payload)
        #expect(sessions.snapshot.isActive)
        #expect(actual.reports.isEmpty)
        #expect(reports.snapshot.reports.isEmpty)
        #expect(window.drawings == 0)
        #expect(stateRead == 0)
        #expect(!sessions.auditLog.contains { $0.capability == reportsID })
    }

    @Test("Outside a session the trigger is refused noActiveSession and draws, reads and audits nothing")
    func triggerOutsideSession() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BugReportsReceiverTests-\(UUID().uuidString)")
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let window = FakeWindow()
        var stateRead = 0
        let reports = DebugDrawerBugReports(
            sessions: sessions, diagnostics: nil, redaction: .standard, limits: .standard,
            state: {
                stateRead += 1
                return ["screen": "checkout"]
            },
            screenshot: window.draw(maximumBytes:),
            now: { clock.now }
        )
        let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
        receiver.enable(.bugReports(reports))
        try receiver.start()
        defer { receiver.stop() }
        let expected = DebugDrawerBugReports.TriggerResult.refused(.noActiveSession)

        let actual = reports.trigger(note: "Shaken on checkout")

        #expect(actual == expected)
        #expect(window.drawings == 0)
        #expect(stateRead == 0)
        #expect(reports.snapshot.reports.isEmpty)
        #expect(sessions.auditLog.isEmpty)
    }

    @Test("Until the host enables it, a trigger in an open session is refused unknownCapability and takes nothing")
    func offUnlessEnabled() throws {
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let window = FakeWindow()
        let reports = DebugDrawerBugReports(
            sessions: sessions, diagnostics: nil, redaction: .standard, limits: .standard, state: nil, screenshot: window.draw(maximumBytes:),
            now: { clock.now }
        )
        sessions.perform(.open(duration: 60))
        let expected = DebugDrawerBugReports.TriggerResult.refused(.unknownCapability)

        let actual = reports.trigger()

        #expect(actual == expected)
        #expect(window.drawings == 0)
        #expect(reports.snapshot.reports.isEmpty)
    }

    @Test("A trigger in a session takes the screenshot, recent lines and state, redacted; the report reaches the store, audited commandApplied")
    func triggerReachesStore() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BugReportsReceiverTests-\(UUID().uuidString)")
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
        let window = FakeWindow()
        let reports = DebugDrawerBugReports(
            sessions: sessions, diagnostics: capture, redaction: .standard, limits: .standard,
            state: { CartState(screen: "checkout", cartItems: 2, customer: .init(email: "jane@example.com", plan: "pro")) },
            screenshot: window.draw(maximumBytes:),
            now: { clock.now }
        )
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.diagnosticsCapture(capture))
        sut.enable(.bugReports(reports))
        let snapshotFile = layout.snapshotFile(for: reportsID)
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        try sut.start()
        defer { sut.stop() }
        capture.log(level: .error, message: "Payment declined for jane@example.com", subsystem: "com.example.shop", category: "checkout")
        let expectedLine = "2026-05-09T06:13:20Z [error] com.example.shop/checkout: Payment declined for [REDACTED]"
        let expectedState = #"{"cartItems":2,"customer":{"email":"[REDACTED]","plan":"pro"},"screen":"checkout"}"#

        let result = reports.trigger(note: "Card for jane@example.com declined")

        func storedReports() throws -> [DebugDrawerBugReports.Report]? {
            guard let data = try? Data(contentsOf: snapshotFile), let document = StoreDocument.decoded(from: data) else { return nil }
            return try JSONDecoder().decode(DebugDrawerBugReports.Snapshot.self, from: document.message.payload).reports
        }
        if try storedReports()?.isEmpty ?? true {
            for await _ in watcher.changes where try !(storedReports()?.isEmpty ?? true) {
                break
            }
        }
        let stored = try #require(try storedReports()?.first)
        guard case let .captured(taken) = result else {
            Issue.record("The trigger was refused: \(result)")
            return
        }
        #expect(stored == taken)
        #expect(stored.screenshot == .png(window.png))
        #expect(window.maximumBytesAsked == DebugDrawerBugReports.Limits.standard.screenshotBytes)
        #expect(stored.note == "Card for [REDACTED] declined")
        #expect(stored.logs.consoleLog == expectedLine)
        #expect(stored.state == .json(expectedState))
        #expect(stored.date == Self.now)
        #expect(sessions.auditLog.last?.capability == reportsID)
        #expect(sessions.auditLog.last?.event == .commandApplied)
        #expect(sessions.auditLog.last?.sessionID == sessions.snapshot.session?.id)
    }

    @Test("Without the diagnostics capture started, a report's logs are notCapturing; without a state closure its state is nil")
    func logsAndStateOptional() throws {
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let reports = DebugDrawerBugReports(
            sessions: sessions, diagnostics: capture, redaction: .standard, limits: .standard, state: nil,
            screenshot: FakeWindow().draw(maximumBytes:),
            now: { clock.now }
        )
        let directory = FileManager.default.temporaryDirectory.appending(path: "BugReportsReceiverTests-\(UUID().uuidString)")
        let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
        receiver.enable(.diagnosticsCapture(capture))
        receiver.enable(.bugReports(reports))
        try receiver.start()
        defer { receiver.stop() }
        sessions.perform(.open(duration: 60))

        let result = reports.trigger()

        guard case let .captured(actual) = result else {
            Issue.record("The trigger was refused: \(result)")
            return
        }
        #expect(actual.logs == .notCapturing)
        #expect(actual.logs.consoleLog.isEmpty)
        #expect(actual.state == nil)
        #expect(actual.note.isEmpty)
    }

    @Test("Made to require a grant, a trigger in a session without one is refused grantMissing and audited")
    func triggerNeedsGrantWhenRequired() throws {
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let window = FakeWindow()
        let reports = DebugDrawerBugReports(
            sessions: sessions, diagnostics: nil, redaction: .standard, limits: .standard, state: nil, screenshot: window.draw(maximumBytes:),
            now: { clock.now }
        )
        let directory = FileManager.default.temporaryDirectory.appending(path: "BugReportsReceiverTests-\(UUID().uuidString)")
        let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
        receiver.enable(.bugReports(reports).requiringGrant())
        try receiver.start()
        defer { receiver.stop() }
        sessions.perform(.open(duration: 60))
        let expected = DebugDrawerBugReports.TriggerResult.refused(.grantMissing)

        let actual = reports.trigger()

        #expect(actual == expected)
        #expect(window.drawings == 0)
        #expect(sessions.auditLog.last?.event == .commandRefused(.grantMissing))
    }

    @Test("While the capability's gate is off a trigger is refused capabilityDisabled; turned off after a report, the report is deleted")
    func gateTurnsItOff() throws {
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let reports = DebugDrawerBugReports(
            sessions: sessions, diagnostics: nil, redaction: .standard, limits: .standard, state: nil, screenshot: FakeWindow().draw(maximumBytes:),
            now: { clock.now }
        )
        let directory = FileManager.default.temporaryDirectory.appending(path: "BugReportsReceiverTests-\(UUID().uuidString)")
        let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let remote = RemoteSwitch()
        receiver.enable(.bugReports(reports)) { remote.isOn }
        try receiver.start()
        defer { receiver.stop() }
        sessions.perform(.open(duration: 60))
        let first = reports.trigger()
        let expected = DebugDrawerBugReports.TriggerResult.refused(.capabilityDisabled)

        remote.isOn = false
        receiver.reevaluateGates()
        let actual = reports.trigger()

        #expect(first != expected)
        #expect(actual == expected)
        #expect(reports.snapshot.reports.isEmpty)
        #expect(sessions.auditLog.contains { $0.capability == reportsID && $0.event == .changeReverted })
    }

    @Test("As the session ends the reports are deleted, audited changeReverted, and their snapshot leaves the store")
    func deletedAtSessionEnd() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BugReportsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let reports = DebugDrawerBugReports(
            sessions: sessions, diagnostics: nil, redaction: .standard, limits: .standard, state: nil, screenshot: FakeWindow().draw(maximumBytes:),
            now: { clock.now }
        )
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.bugReports(reports))
        try sut.start()
        defer { sut.stop() }
        sessions.perform(.open(duration: 60))
        reports.trigger()
        let snapshotFile = layout.snapshotFile(for: reportsID)
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }
        func storedReports() -> [DebugDrawerBugReports.Report]? {
            guard let data = try? Data(contentsOf: snapshotFile), let document = StoreDocument.decoded(from: data) else { return nil }
            return try? JSONDecoder().decode(DebugDrawerBugReports.Snapshot.self, from: document.message.payload).reports
        }
        if storedReports()?.count != 1 {
            for await _ in watcher.changes where storedReports()?.count == 1 {
                break
            }
        }

        sessions.end()

        #expect(reports.snapshot.reports.isEmpty)
        #expect(reports.snapshot.sessionID == nil)
        #expect(!FileManager.default.fileExists(atPath: snapshotFile.path))
        #expect(sessions.auditLog.contains { $0.capability == reportsID && $0.event == .changeReverted })
    }

    @Test("A report file left by a launch killed during a session is removed as the next launch enables the capability")
    func leftoverRemovedAtEnable() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "BugReportsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let snapshotFile = layout.snapshotFile(for: reportsID)
        try layout.write(Data("left behind".utf8), to: snapshotFile)
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let reports = DebugDrawerBugReports(
            sessions: sessions, diagnostics: nil, redaction: .standard, limits: .standard, state: nil, screenshot: FakeWindow().draw(maximumBytes:),
            now: { clock.now }
        )
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)

        sut.enable(.bugReports(reports))

        #expect(!FileManager.default.fileExists(atPath: snapshotFile.path))
    }

    @Test("The sidecar's export is recorded and its delete removes the report; a command naming no report is refused notExposed")
    func sidecarExportsAndDeletes() throws {
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let reports = DebugDrawerBugReports(
            sessions: sessions, diagnostics: nil, redaction: .standard, limits: .standard, state: nil, screenshot: FakeWindow().draw(maximumBytes:),
            now: { clock.now }
        )
        let directory = FileManager.default.temporaryDirectory.appending(path: "BugReportsReceiverTests-\(UUID().uuidString)")
        let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
        receiver.enable(.bugReports(reports))
        try receiver.start()
        defer { receiver.stop() }
        sessions.perform(.open(duration: 60))
        guard case let .captured(taken) = reports.trigger() else {
            Issue.record("The trigger was refused")
            return
        }
        let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
        let commands: [DebugDrawerBugReports.Command] = [.export(id: taken.id), .delete(id: UUID()), .delete(id: taken.id)]
        for (index, command) in commands.enumerated() {
            let document = try StoreDocument(TransportMessage(kind: .command, pluginID: reportsID, payload: TransportMessage.payload(command)))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let expectedExports = [DebugDrawerBugReports.Export(reportID: taken.id, date: Self.now)]

        receiver.reevaluateGates()

        let events = sessions.auditLog.filter { $0.capability == reportsID }.map(\.event)
        #expect(reports.snapshot.reports.isEmpty)
        #expect(reports.snapshot.exports == expectedExports)
        #expect(events == [.commandApplied, .commandApplied, .commandRefused(.notExposed), .commandApplied])
    }

    @Test("The bounds: the oldest report goes first, the newest lines are kept, and a state over stateBytes is left out with its size")
    func bounded() throws {
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let limits = try DebugDrawerBugReports.Limits(reports: 2, logLines: 1, stateBytes: 10, screenshotBytes: 100)
        let window = FakeWindow()
        let reports = DebugDrawerBugReports(
            sessions: sessions, diagnostics: capture, redaction: .standard, limits: limits,
            state: { ["screen": "a screen name longer than ten bytes"] },
            screenshot: window.draw(maximumBytes:),
            now: { clock.now }
        )
        let directory = FileManager.default.temporaryDirectory.appending(path: "BugReportsReceiverTests-\(UUID().uuidString)")
        let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
        receiver.enable(.diagnosticsCapture(capture))
        receiver.enable(.bugReports(reports))
        try receiver.start()
        defer { receiver.stop() }
        sessions.perform(.open(duration: 60))
        sessions.apply(to: captureID, scope: .session { capture.perform(.stop) }) {
            capture.perform(.start)
            return true
        }
        capture.log(level: .info, message: "first")
        capture.log(level: .info, message: "second")
        let expectedStateSize = 48

        let notes = ["one", "two", "three"].map { note in reports.trigger(note: note) }

        let kept = reports.snapshot.reports
        #expect(notes.allSatisfy { if case .captured = $0 { true } else { false } })
        #expect(kept.map(\.note) == ["two", "three"])
        #expect(kept.last?.logs.consoleLog.hasSuffix("second") == true)
        #expect(kept.last.map { if case let .captured(lines) = $0.logs { lines.count } else { -1 } } == 1)
        #expect(kept.last?.state == .omitted(.tooLarge, byteCount: expectedStateSize))
        #expect(window.maximumBytesAsked == 100)
    }

    @Test("Triggering, reading, exporting and deleting a report send no request through the URL loading system")
    func noUploadRequests() async throws {
        #expect(URLProtocol.registerClass(RequestSpy.self))
        defer { URLProtocol.unregisterClass(RequestSpy.self) }
        RequestSpy.seen.withLock { $0 = [] }
        let directory = FileManager.default.temporaryDirectory.appending(path: "BugReportsReceiverTests-\(UUID().uuidString)")
        let clock = MovableClock(Self.now)
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: clock, timer: ManualTimer())
        let capture = DebugDrawerDiagnosticsCapture(sessions: sessions, redaction: .standard, limits: .standard) { clock.now }
        let reports = DebugDrawerBugReports(
            sessions: sessions, diagnostics: capture, redaction: .standard, limits: .standard,
            state: { ["screen": "checkout"] }, screenshot: FakeWindow().draw(maximumBytes:),
            now: { clock.now }
        )
        let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
        receiver.enable(.diagnosticsCapture(capture))
        receiver.enable(.bugReports(reports))
        try receiver.start()
        defer { receiver.stop() }
        sessions.perform(.open(duration: 60))

        guard case let .captured(taken) = reports.trigger(note: "Checkout froze") else {
            Issue.record("The trigger was refused")
            return
        }
        let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
        for (index, command) in [DebugDrawerBugReports.Command.export(id: taken.id), .delete(id: taken.id)].enumerated() {
            let document = try StoreDocument(TransportMessage(kind: .command, pluginID: reportsID, payload: TransportMessage.payload(command)))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        receiver.reevaluateGates()
        sessions.end()

        #expect(RequestSpy.seen.withLock { $0 }.isEmpty)
        #expect(reports.snapshot.reports.isEmpty)
    }
}
