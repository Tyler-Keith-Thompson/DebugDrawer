@testable import DebugDrawerReceiver
import DebugDrawerTestSupport
import Foundation
import Testing

/// A flag service with nothing to override, so a receiver serves a capability other than the
/// auth actions.
@MainActor
private final class EmptyFlagAdapter: DebugDrawerFeatureFlagAdapter {
    func overridableFlags() -> [DebugDrawerFeatureFlag] { [] }
    func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {}
    func clearOverride(forKey key: String) {}
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

/// The app's sign-in, as its handlers change it, read back by the tests.
@MainActor
private final class FakeAuth {
    private(set) var calls: [String] = []

    var actions: [DebugDrawerAuthAction] {
        [
            .expireAccessToken { [weak self] in
                self?.calls.append("expire")
                return .succeeded
            },
            .logOut { [weak self] in
                self?.calls.append("log out")
                return .succeeded
            }
        ]
    }
}

// The auth actions end to end through the receiver alone, as a release build links it: a request
// in a session runs the host's handler and is audited, anything else is refused before a handler
// runs, and nothing is served until the host enables it. Commands are files left in the store the
// way a sidecar's transport leaves them; the receiver performs those waiting as it starts.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AuthActionsReceiverTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let actionsID = DebugDrawerAuthActions.pluginID
    private let flagsID = DebugDrawerFeatureFlagOverrides.pluginID
    private let sessionsID = DebugDrawerSessions.pluginID

    @Test("A request in a session runs the action's handler and is audited as applied; its outcome lands in the snapshot")
    func requestRunsHandler() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AuthActionsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let auth = FakeAuth()
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (actionsID, TransportMessage.payload(DebugDrawerAuthActions.Command.perform(action: "expire-access-token"))),
            (actionsID, TransportMessage.payload(DebugDrawerAuthActions.Command.perform(action: "log-out")))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let model = DebugDrawerAuthActions(actions: auth.actions, launchURL: nil, now: { Self.now })
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.authActions(model))
        let expectedCalls = ["expire", "log out"]
        let expectedEvents: [DebugDrawerAuditEntry.Event] = [.commandApplied, .commandApplied]
        let expectedRuns = [
            DebugDrawerAuthActions.Run(number: 1, started: Self.now, status: .succeeded),
            DebugDrawerAuthActions.Run(number: 2, started: Self.now, status: .succeeded)
        ]

        try sut.start()
        defer { sut.stop() }
        for await snapshot in model.$snapshot.values where snapshot.actions.allSatisfy({ $0.lastRun?.status == .succeeded }) {
            break
        }

        let actual = sessions.auditLog.filter { $0.capability == actionsID }
        #expect(auth.calls == expectedCalls)
        #expect(actual.map(\.event) == expectedEvents)
        #expect(model.snapshot.actions.map(\.lastRun) == expectedRuns)
    }

    @Test("A request for an action the host didn't register is refused notExposed, one that doesn't decode malformedCommand; no handler runs")
    func unknownActionIsRefused() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AuthActionsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let auth = FakeAuth()
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (actionsID, TransportMessage.payload(DebugDrawerAuthActions.Command.perform(action: "force-refresh"))),
            (actionsID, Data(#"{"perform":{"name":"log-out"}}"#.utf8)),
            (actionsID, Data(#"{"readToken":{}}"#.utf8))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let model = DebugDrawerAuthActions(actions: auth.actions, launchURL: nil, now: { Self.now })
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.authActions(model))
        let expectedEvents: [DebugDrawerAuditEntry.Event] = [
            .commandRefused(.notExposed), .commandRefused(.malformedCommand), .commandRefused(.malformedCommand)
        ]

        try sut.start()
        defer { sut.stop() }

        let actual = sessions.auditLog.filter { $0.capability == actionsID }
        #expect(actual.map(\.event) == expectedEvents)
        #expect(model.snapshot.actions.allSatisfy { $0.lastRun == nil })
    }

    @Test("Outside a session a request is refused noActiveSession and no handler runs")
    func requestOutsideSessionIsRefused() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AuthActionsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let auth = FakeAuth()
        let payload = try TransportMessage.payload(DebugDrawerAuthActions.Command.perform(action: "log-out"))
        let document = StoreDocument(TransportMessage(kind: .command, pluginID: actionsID, payload: payload))
        try layout.write(document.encoded(), to: layout.commands.appending(path: "0.json"))
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let model = DebugDrawerAuthActions(actions: auth.actions, launchURL: nil, now: { Self.now })
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.authActions(model))
        let expectedEvent = DebugDrawerAuditEntry.Event.commandRefused(.noActiveSession)

        try sut.start()
        defer { sut.stop() }

        #expect(sessions.auditLog.last?.event == expectedEvent)
        #expect(model.snapshot.actions.allSatisfy { $0.lastRun == nil })
    }

    @Test("Until the host enables it, a request is refused unknownCapability in an open session; nothing is served or run")
    func offUnlessEnabled() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AuthActionsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let auth = FakeAuth()
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (actionsID, TransportMessage.payload(DebugDrawerAuthActions.Command.perform(action: "log-out")))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let flagSuite = temporarySuiteName("AuthActionsReceiverTests.flags")
        let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
        defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: EmptyFlagAdapter(), defaults: flagDefaults)))
        _ = auth.actions
        let expectedEnabled = [flagsID]

        try sut.start()
        defer { sut.stop() }

        let session = try #require(sessions.snapshot.session)
        let expectedEntry = DebugDrawerAuditEntry(
            date: Self.now, sessionID: session.id, capability: actionsID, event: .commandRefused(.unknownCapability)
        )
        #expect(sessions.auditLog.last == expectedEntry)
        #expect(auth.calls.isEmpty)
        #expect(sut.enabledCapabilities == expectedEnabled)
        #expect(!FileManager.default.fileExists(atPath: layout.snapshotFile(for: actionsID).path))
    }

    @Test("With requiringGrant(), a request in a session without a grant is refused grantMissing and no handler runs")
    func requiringGrantRefusesWithoutGrant() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "AuthActionsReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let auth = FakeAuth()
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (actionsID, TransportMessage.payload(DebugDrawerAuthActions.Command.perform(action: "log-out")))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let model = DebugDrawerAuthActions(actions: auth.actions, launchURL: nil, now: { Self.now })
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.authActions(model).requiringGrant())
        let expectedEvent = DebugDrawerAuditEntry.Event.commandRefused(.grantMissing)

        try sut.start()
        defer { sut.stop() }

        #expect(sessions.auditLog.last?.event == expectedEvent)
        #expect(model.snapshot.actions.allSatisfy { $0.lastRun == nil })
    }
}
