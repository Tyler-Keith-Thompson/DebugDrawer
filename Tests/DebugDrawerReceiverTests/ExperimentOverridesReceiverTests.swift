@testable import DebugDrawerReceiver
import Foundation
import Testing

/// An experiment service the test reads back, standing in for one that keeps its forced variants
/// across launches: the same instance is handed to the receiver of each launch. It records every
/// exclusion report, as a host's analytics would act on it.
@MainActor
private final class FakeExperimentAdapter: DebugDrawerExperimentAdapter {
    let variants: [String: [String]]
    let assignments: [String: String]
    private(set) var forced: [String: String] = [:]
    private(set) var exclusionReports: [[String]] = []

    init(variants: [String: [String]], assignments: [String: String]) {
        self.variants = variants
        self.assignments = assignments
    }

    func overridableExperiments() -> [DebugDrawerExperiment] {
        variants.keys.sorted().map { key in
            DebugDrawerExperiment(key: key, variants: variants[key]!, assignedVariant: forced[key] ?? assignments[key])
        }
    }

    func setOverride(variant: String, forExperiment key: String) {
        forced[key] = variant
    }

    func clearOverride(forExperiment key: String) {
        forced[key] = nil
    }

    func overriddenExperimentsDidChange(_ keys: [String]) {
        exclusionReports.append(keys)
    }
}

/// A flag service with nothing to override, so a receiver serves a capability other than
/// experiments.
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

// The experiment overrides capability end to end through the receiver alone, as a release build
// links it (no drawer): what a sidecar sees, what it may force, how the host hears that this device
// must be left out of the experiments' analytics (during the session and past it), and that nothing
// is served until the host enables it. Commands are files left in the store the way a sidecar's
// transport leaves them; the receiver performs those waiting as it starts. Each test keeps the
// model's record of what it overrode in a defaults suite of its own.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ExperimentOverridesReceiverTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let experimentsID = DebugDrawerExperimentOverrides.pluginID
    private let flagsID = DebugDrawerFeatureFlagOverrides.pluginID
    private let sessionsID = DebugDrawerSessions.pluginID

    @Test("In a session, a sidecar reads, from the store, each experiment the adapter lists with its variants and the app's assignment")
    func listsExperimentsWithVariantsAndAssignment() async throws {
        let suite = "ExperimentOverridesReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "ExperimentOverridesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeExperimentAdapter(
            variants: ["checkout-flow": ["control", "one-page"], "onboarding": ["control", "video", "quiz"]],
            assignments: ["checkout-flow": "control"]
        )
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.experimentOverrides(DebugDrawerExperimentOverrides(adapter: adapter, defaults: defaults)))
        let snapshotFile = layout.snapshotFile(for: experimentsID)
        let expected = DebugDrawerExperimentOverrides.Snapshot(
            experiments: [
                DebugDrawerExperiment(key: "checkout-flow", variants: ["control", "one-page"], assignedVariant: "control"),
                DebugDrawerExperiment(key: "onboarding", variants: ["control", "video", "quiz"], assignedVariant: nil)
            ],
            overriddenKeys: []
        )
        let watcher = try #require(DirectoryWatcher(directory: layout.snapshots))
        defer { watcher.cancel() }

        sessions.perform(.open(duration: 60))
        try sut.start()
        defer { sut.stop() }
        if !FileManager.default.fileExists(atPath: snapshotFile.path) {
            for await _ in watcher.changes where FileManager.default.fileExists(atPath: snapshotFile.path) {
                break
            }
        }

        let document = try #require(StoreDocument.decoded(from: Data(contentsOf: snapshotFile)))
        let actual = try JSONDecoder().decode(DebugDrawerExperimentOverrides.Snapshot.self, from: document.message.payload)
        #expect(document.message.kind == .snapshot)
        #expect(actual == expected)
    }

    @Test("Only a listed experiment is forced, into one of its variants: an unlisted one is refused notExposed, an unknown variant malformedCommand")
    func onlyListedExperimentsAndVariantsChange() throws {
        let suite = "ExperimentOverridesReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "ExperimentOverridesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeExperimentAdapter(variants: ["checkout-flow": ["control", "one-page"]], assignments: ["checkout-flow": "control"])
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (experimentsID, TransportMessage.payload(DebugDrawerExperimentOverrides.Command.setOverride(experiment: "pricing", variant: "free"))),
            (
                experimentsID,
                TransportMessage.payload(DebugDrawerExperimentOverrides.Command.setOverride(experiment: "checkout-flow", variant: "two-page"))
            ),
            (experimentsID, TransportMessage.payload(DebugDrawerExperimentOverrides.Command.clearOverride(experiment: "pricing"))),
            (
                experimentsID,
                TransportMessage.payload(DebugDrawerExperimentOverrides.Command.setOverride(experiment: "checkout-flow", variant: "one-page"))
            )
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let model = DebugDrawerExperimentOverrides(adapter: adapter, defaults: defaults)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.experimentOverrides(model))
        let expectedForced = ["checkout-flow": "one-page"]
        let expectedEvents: [DebugDrawerAuditEntry.Event] = [
            .commandRefused(.notExposed),
            .commandRefused(.malformedCommand),
            .commandRefused(.notExposed),
            .commandApplied
        ]
        let expectedKeys = ["checkout-flow"]

        try sut.start()
        defer { sut.stop() }

        let actual = sessions.auditLog.filter { $0.capability == experimentsID }
        #expect(adapter.forced == expectedForced)
        #expect(actual.map(\.event) == expectedEvents)
        #expect(model.snapshot.overriddenKeys == expectedKeys)
    }

    @Test("The host hears the overridden experiments as the model is made, at each change and as the session ends, and can read them at any time")
    func overridesAreReportedForAnalyticsExclusion() throws {
        let suite = "ExperimentOverridesReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "ExperimentOverridesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeExperimentAdapter(
            variants: ["checkout-flow": ["control", "one-page"], "onboarding": ["control", "video"]],
            assignments: ["checkout-flow": "control", "onboarding": "control"]
        )
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (experimentsID, TransportMessage.payload(DebugDrawerExperimentOverrides.Command.setOverride(experiment: "onboarding", variant: "video"))),
            (
                experimentsID,
                TransportMessage.payload(DebugDrawerExperimentOverrides.Command.setOverride(experiment: "checkout-flow", variant: "one-page"))
            ),
            (
                experimentsID,
                TransportMessage.payload(DebugDrawerExperimentOverrides.Command.setOverride(experiment: "checkout-flow", variant: "control"))
            )
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let model = DebugDrawerExperimentOverrides(adapter: adapter, defaults: defaults)
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        sut.enable(.experimentOverrides(model))
        try sut.start()
        defer { sut.stop() }
        let duringSession = (keys: model.overriddenExperiments, isExcluded: model.isExcludedFromAnalytics)
        let expectedDuringSession = ["checkout-flow", "onboarding"]
        let expectedReports = [[], ["onboarding"], ["checkout-flow", "onboarding"], []]

        sessions.end()

        #expect(duringSession.keys == expectedDuringSession)
        #expect(duringSession.isExcluded)
        #expect(adapter.exclusionReports == expectedReports)
        #expect(model.overriddenExperiments.isEmpty)
        #expect(!model.isExcludedFromAnalytics)
        #expect(adapter.forced.isEmpty)
        #expect(sessions.auditLog.last?.event == .sessionEnded(.ended))
    }

    @Test("Persistent overrides keep the device excluded past the session and a relaunch, reported as the next model is made, until cleared")
    func persistentOverridesStayExcludedAcrossRelaunch() throws {
        let suite = "ExperimentOverridesReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "ExperimentOverridesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeExperimentAdapter(variants: ["checkout-flow": ["control", "one-page"]], assignments: ["checkout-flow": "control"])
        let set = try TransportMessage.payload(DebugDrawerExperimentOverrides.Command.setOverride(experiment: "checkout-flow", variant: "one-page"))
        let setDocument = StoreDocument(TransportMessage(kind: .command, pluginID: experimentsID, payload: set))
        try layout.write(setDocument.encoded(), to: layout.commands.appending(path: "0.json"))
        let firstSessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let firstModel = DebugDrawerExperimentOverrides(adapter: adapter, defaults: defaults)
        let firstLaunch = DebugDrawerReceiver(directory: directory, sessions: firstSessions)
        firstLaunch.enable(.experimentOverrides(firstModel, scope: .persistent))
        firstSessions.perform(.open(duration: 60))
        try firstLaunch.start()
        firstSessions.end()
        firstLaunch.stop()
        let excludedAfterSession = firstModel.isExcludedFromAnalytics
        let reportsBeforeRelaunch = adapter.exclusionReports.count
        let clear = try TransportMessage.payload(DebugDrawerExperimentOverrides.Command.clearOverride(experiment: "checkout-flow"))
        let clearDocument = StoreDocument(TransportMessage(kind: .command, pluginID: experimentsID, payload: clear))
        try layout.write(clearDocument.encoded(), to: layout.commands.appending(path: "1.json"))
        let secondSessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let model = DebugDrawerExperimentOverrides(adapter: adapter, defaults: defaults)
        let atRelaunch = (keys: model.overriddenExperiments, report: adapter.exclusionReports.dropFirst(reportsBeforeRelaunch).first)
        let sut = DebugDrawerReceiver(directory: directory, sessions: secondSessions)
        sut.enable(.experimentOverrides(model, scope: .persistent))
        secondSessions.perform(.open(duration: 60))
        let expectedKeys = ["checkout-flow"]

        try sut.start()
        defer { sut.stop() }

        #expect(excludedAfterSession)
        #expect(atRelaunch.keys == expectedKeys)
        #expect(atRelaunch.report == expectedKeys)
        #expect(adapter.forced.isEmpty)
        #expect(!model.isExcludedFromAnalytics)
        #expect(adapter.exclusionReports.last == [])
        #expect(secondSessions.auditLog.last?.event == .commandApplied)
    }

    @Test("Session overrides left by a quit are cleared as the next launch makes the capability, and the host hears none is left")
    func sessionOverridesLeftByQuitAreCleared() throws {
        let suite = "ExperimentOverridesReceiverTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let directory = FileManager.default.temporaryDirectory.appending(path: "ExperimentOverridesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeExperimentAdapter(variants: ["checkout-flow": ["control", "one-page"]], assignments: ["checkout-flow": "control"])
        let set = try TransportMessage.payload(DebugDrawerExperimentOverrides.Command.setOverride(experiment: "checkout-flow", variant: "one-page"))
        let setDocument = StoreDocument(TransportMessage(kind: .command, pluginID: experimentsID, payload: set))
        try layout.write(setDocument.encoded(), to: layout.commands.appending(path: "0.json"))
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let quitLaunch = DebugDrawerReceiver(directory: directory, sessions: sessions)
        quitLaunch.enable(.experimentOverrides(DebugDrawerExperimentOverrides(adapter: adapter, defaults: defaults)))
        sessions.perform(.open(duration: 60))
        try quitLaunch.start()
        // The app quits with the session open: nothing ends it, so its revert never runs.
        quitLaunch.stop()
        let afterQuit = adapter.forced
        let model = DebugDrawerExperimentOverrides(adapter: adapter, defaults: defaults)
        let expectedAfterQuit = ["checkout-flow": "one-page"]
        let expectedLastReports = [["checkout-flow"], []]

        _ = DebugDrawerReceiverCapability.experimentOverrides(model)

        #expect(afterQuit == expectedAfterQuit)
        #expect(adapter.forced.isEmpty)
        #expect(!model.isExcludedFromAnalytics)
        #expect(Array(adapter.exclusionReports.suffix(2)) == expectedLastReports)
    }

    @Test("Until the host enables it, a command to the capability is refused unknownCapability in an open session; nothing is served or forced")
    func offUnlessEnabled() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ExperimentOverridesReceiverTests-\(UUID().uuidString)")
        let layout = AppGroupStoreLayout(directory: AppGroupStoreLayout.appDirectory(inStore: directory))
        #expect(layout.create())
        let adapter = FakeExperimentAdapter(variants: ["checkout-flow": ["control", "one-page"]], assignments: ["checkout-flow": "control"])
        let commands: [(String, Data)] = try [
            (sessionsID, TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60))),
            (
                experimentsID,
                TransportMessage.payload(DebugDrawerExperimentOverrides.Command.setOverride(experiment: "checkout-flow", variant: "one-page"))
            )
        ]
        for (index, (id, payload)) in commands.enumerated() {
            let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
            try layout.write(document.encoded(), to: layout.commands.appending(path: "\(index).json"))
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300, auditCapacity: 100, clock: FixedClock(now: Self.now), timer: IdleTimer())
        let sut = DebugDrawerReceiver(directory: directory, sessions: sessions)
        let flagSuite = "ExperimentOverridesReceiverTests.flags.\(UUID().uuidString)"
        let flagDefaults = try #require(UserDefaults(suiteName: flagSuite))
        defer { flagDefaults.removePersistentDomain(forName: flagSuite) }
        sut.enable(.featureFlagOverrides(DebugDrawerFeatureFlagOverrides(adapter: EmptyFlagAdapter(), defaults: flagDefaults)))
        let expectedEnabled = [flagsID]

        try sut.start()
        defer { sut.stop() }

        let session = try #require(sessions.snapshot.session)
        let expectedEntry = DebugDrawerAuditEntry(
            date: Self.now, sessionID: session.id, capability: experimentsID, event: .commandRefused(.unknownCapability)
        )
        #expect(sessions.auditLog.last == expectedEntry)
        #expect(adapter.forced.isEmpty)
        #expect(adapter.exclusionReports.isEmpty)
        #expect(sut.enabledCapabilities == expectedEnabled)
        #expect(!FileManager.default.fileExists(atPath: layout.snapshotFile(for: experimentsID).path))
    }
}
