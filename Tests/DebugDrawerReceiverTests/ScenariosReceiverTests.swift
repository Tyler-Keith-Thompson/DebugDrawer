@testable import DebugDrawerReceiver
import Foundation
import Testing

/// A flag service with nothing to override, so a receiver serves a capability other than
/// scenarios.
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

/// Where the app's handlers put it, as a router would, read back by the tests.
@MainActor
private final class FakeRouter {
    private(set) var visits: [String] = []

    var scenarios: [DebugDrawerScenario] {
        [
            DebugDrawerScenario("open-order", title: "Open Order", summary: "The order's detail screen", parameters: [
                .integer("orderID", title: "Order", default: 123, in: 1 ... 999_999),
                .boolean("showReceipt", title: "Show Receipt")
            ]) { [unowned self] arguments in
                visits.append("order \(arguments.integer("orderID") ?? -1) receipt \(arguments.boolean("showReceipt") ?? false)")
            },
            DebugDrawerScenario("show-paywall", title: "Show Paywall", parameters: [
                .choice("plan", title: "Plan", options: ["monthly", "annual"]),
                .string("promo", title: "Promo Code", maximumLength: 8)
            ]) { [unowned self] arguments in
                visits.append("paywall \(arguments.string("plan") ?? "?") promo \(arguments.string("promo") ?? "?")")
            }
        ]
    }
}

// The scenario launcher end to end through the receiver alone, as a release build links it (no
// drawer): what a sidecar lists, that a launch runs the host's handler with only the declared
// parameters, typed, and that anything else is refused before a handler runs, and that nothing is
// served until the host enables it. Commands are files left in the store the way a sidecar's
// transport leaves them; the receiver performs those waiting as it starts, as it does those a
// sidecar left while the app was in the background once it comes to the foreground.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ScenariosReceiverTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let scenariosID = DebugDrawerScenarios.pluginID
    private let flagsID = DebugDrawerFeatureFlagOverrides.pluginID
    private let sessionsID = DebugDrawerSessions.pluginID

    @Test("A sidecar reads, from the store, each scenario the host registered with its declared parameters and the launch URL")
    func listsScenariosWithParameters() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ScenariosReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let router = FakeRouter()
        let launchURL = try #require(URL(string: "shop-internal://scenarios"))
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.scenarios(router.scenarios, launchURL: launchURL))
        let snapshotFile = layout.snapshotFile(for: scenariosID)
        let expected = DebugDrawerScenarios.Snapshot(
            scenarios: [
                DebugDrawerScenarios.Entry(id: "open-order", title: "Open Order", summary: "The order's detail screen", parameters: [
                    DebugDrawerScenarioParameter(name: "orderID", title: "Order", kind: .integer(range: 1 ... 999_999), defaultValue: .integer(123)),
                    DebugDrawerScenarioParameter(name: "showReceipt", title: "Show Receipt", kind: .boolean, defaultValue: .boolean(false))
                ]),
                DebugDrawerScenarios.Entry(id: "show-paywall", title: "Show Paywall", summary: "", parameters: [
                    DebugDrawerScenarioParameter(
                        name: "plan", title: "Plan", kind: .choice(options: ["monthly", "annual"]), defaultValue: .string("monthly")
                    ),
                    DebugDrawerScenarioParameter(name: "promo", title: "Promo Code", kind: .string(maximumLength: 8), defaultValue: .string(""))
                ])
            ],
            launchURL: launchURL,
            lastRun: nil
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
        let actual = try JSONDecoder().decode(DebugDrawerScenarios.Snapshot.self, from: document.message.payload)
        #expect(document.message.kind == .snapshot)
        #expect(actual == expected)
    }

    @Test("A launch in a session runs the scenario's handler with the declared parameters, typed, defaults for those left out; audited as applied")
    func launchRunsHandlerWithDeclaredParameters() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ScenariosReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let router = FakeRouter()
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (
                scenariosID,
                TransportMessage.payload(DebugDrawerScenarios.Command.run(
                    scenario: "open-order", arguments: ["orderID": .integer(42), "showReceipt": .boolean(true)]
                ))
            ),
            (
                scenariosID,
                TransportMessage.payload(DebugDrawerScenarios.Command.run(scenario: "show-paywall", arguments: ["plan": .string("annual")]))
            )
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let model = DebugDrawerScenarios(scenarios: router.scenarios, launchURL: nil, now: { Self.now })
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.scenarios(model))
        let expectedVisits = ["order 42 receipt true", "paywall annual promo "]
        let expectedEvents: [DebugDrawerAuditEntry.Event] = [.commandApplied, .commandApplied]
        let expectedLastRun = DebugDrawerScenarios.Run(number: 2, scenario: "show-paywall", date: Self.now)

        try sut.start()
        defer { sut.stop() }

        let actual = sessions.auditLog.filter { $0.capability == scenariosID }
        #expect(router.visits == expectedVisits)
        #expect(actual.map(\.event) == expectedEvents)
        #expect(model.snapshot.lastRun == expectedLastRun)
    }

    @Test(
        "An unknown scenario is refused notExposed; an undeclared parameter or a value its parameter doesn't take malformedCommand; no handler runs"
    )
    func unknownScenarioOrParameterIsRefused() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ScenariosReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let router = FakeRouter()
        let refused: [DebugDrawerScenarios.Command] = [
            .run(scenario: "delete-account", arguments: [:]),
            .run(scenario: "open-order", arguments: ["orderID": .integer(42), "userID": .string("admin")]),
            .run(scenario: "open-order", arguments: ["orderID": .string("42")]),
            .run(scenario: "open-order", arguments: ["orderID": .integer(0)]),
            .run(scenario: "open-order", arguments: ["orderID": .integer(1_000_000)]),
            .run(scenario: "open-order", arguments: ["showReceipt": .integer(1)]),
            .run(scenario: "show-paywall", arguments: ["plan": .string("lifetime")]),
            .run(scenario: "show-paywall", arguments: ["plan": .boolean(true)]),
            .run(scenario: "show-paywall", arguments: ["promo": .string("TOOLONGCODE")])
        ]
        var commands: [(String, Data)] = try [(sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60)))]
        commands += try refused.map { try (scenariosID, TransportMessage.payload($0)) }
        commands.append((scenariosID, Data(#"{"run":{"scenario":"open-order","arguments":{"orderID":{"double":{"_0":4.2}}}}}"#.utf8)))
        commands.append((scenariosID, Data(#"{"evaluate":{"script":"exit(0)"}}"#.utf8)))
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: String(format: "%03d.json", index)))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let model = DebugDrawerScenarios(scenarios: router.scenarios, launchURL: nil, now: { Self.now })
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.scenarios(model))
        let expectedEvents: [DebugDrawerAuditEntry.Event] = [.commandRefused(.notExposed)]
            + Array(repeating: .commandRefused(.malformedCommand), count: 10)

        try sut.start()
        defer { sut.stop() }

        let actual = sessions.auditLog.filter { $0.capability == scenariosID }
        #expect(actual.map(\.event) == expectedEvents)
        #expect(router.visits.isEmpty)
        #expect(model.snapshot.lastRun == nil)
    }

    @Test("Outside a session a launch is refused noActiveSession and no handler runs")
    func launchOutsideSessionIsRefused() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ScenariosReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let router = FakeRouter()
        let payload = try TransportMessage.payload(DebugDrawerScenarios.Command.run(scenario: "open-order", arguments: [:]))
        let document = StoreDocument(TransportMessage(kind: .command, pluginID: scenariosID, payload: payload))
        try layout.write(document.encoded(), to: layout.commands.appending(path: "0.json"))
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.scenarios(router.scenarios))
        let expectedEvent = DebugDrawerAuditEntry.Event.commandRefused(.noActiveSession)

        try sut.start()
        defer { sut.stop() }

        #expect(sessions.auditLog.last?.event == expectedEvent)
        #expect(router.visits.isEmpty)
    }

    @Test("Until the host enables it, a launch is refused unknownCapability in an open session; nothing is served or run")
    func offUnlessEnabled() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ScenariosReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let router = FakeRouter()
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (scenariosID, TransportMessage.payload(DebugDrawerScenarios.Command.run(scenario: "open-order", arguments: [:])))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.featureFlagOverrides(EmptyFlagAdapter()))
        _ = router.scenarios
        let expectedEnabled = [flagsID]

        try sut.start()
        defer { sut.stop() }

        let session = try #require(sessions.snapshot.session)
        let expectedEntry = DebugDrawerAuditEntry(
            date: Self.now, sessionID: session.id, capability: scenariosID, event: .commandRefused(.unknownCapability)
        )
        #expect(sessions.auditLog.last == expectedEntry)
        #expect(router.visits.isEmpty)
        #expect(sut.enabledCapabilities == expectedEnabled)
        #expect(!FileManager.default.fileExists(atPath: layout.snapshotFile(for: scenariosID).path))
    }

    @Test("With requiringGrant(), a launch in a session without a grant is refused grantMissing and no handler runs")
    func requiringGrantRefusesWithoutGrant() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ScenariosReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let router = FakeRouter()
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (scenariosID, TransportMessage.payload(DebugDrawerScenarios.Command.run(scenario: "open-order", arguments: [:])))
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.scenarios(router.scenarios).requiringGrant())
        let expectedEvent = DebugDrawerAuditEntry.Event.commandRefused(.grantMissing)

        try sut.start()
        defer { sut.stop() }

        #expect(sessions.auditLog.last?.event == expectedEvent)
        #expect(router.visits.isEmpty)
    }
}
