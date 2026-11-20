import DebugDrawerReceiver
import Foundation
import Testing

/// An experiment service the test reads back, with a forced variant of the host's own allowed.
@MainActor
private final class FakeExperimentAdapter: DebugDrawerExperimentAdapter {
    let variants: [String: [String]]
    var forced: [String: String] = [:]
    private(set) var exclusionReports: [[String]] = []

    init(variants: [String: [String]]) {
        self.variants = variants
    }

    func overridableExperiments() -> [DebugDrawerExperiment] {
        variants.keys.sorted().map { DebugDrawerExperiment(key: $0, variants: variants[$0]!, assignedVariant: forced[$0] ?? variants[$0]!.first) }
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

// The experiment overrides capability's model, driven directly: what it lets a caller change and
// what it tells the host.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ExperimentOverridesTests {
    @Test("A forced variant reaches the adapter and the snapshot, which lists the experiment as overridden")
    func forcesListedVariant() throws {
        let suite = "ExperimentOverridesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let adapter = FakeExperimentAdapter(variants: ["checkout-flow": ["control", "one-page"]])
        let sut = DebugDrawerExperimentOverrides(adapter: adapter, defaults: defaults)
        let expected = DebugDrawerExperimentOverrides.Snapshot(
            experiments: [DebugDrawerExperiment(key: "checkout-flow", variants: ["control", "one-page"], assignedVariant: "one-page")],
            overriddenKeys: ["checkout-flow"]
        )

        sut.perform(.setOverride(experiment: "checkout-flow", variant: "one-page"))

        #expect(sut.snapshot == expected)
    }

    @Test("Performed directly, an unlisted experiment or a variant the experiment doesn't have changes nothing and reports nothing")
    func ignoresUnlistedAndUnknownVariant() throws {
        let suite = "ExperimentOverridesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let adapter = FakeExperimentAdapter(variants: ["checkout-flow": ["control", "one-page"]])
        let sut = DebugDrawerExperimentOverrides(adapter: adapter, defaults: defaults)
        let expected = sut.snapshot
        let expectedReports: [[String]] = [[]]

        sut.perform(.setOverride(experiment: "pricing", variant: "free"))
        sut.perform(.setOverride(experiment: "checkout-flow", variant: "two-page"))

        #expect(adapter.forced.isEmpty)
        #expect(sut.snapshot == expected)
        #expect(adapter.exclusionReports == expectedReports)
    }

    @Test("Clearing removes only the variants the model forced, never the host's own")
    func clearsOnlyItsOwn() throws {
        let suite = "ExperimentOverridesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let adapter = FakeExperimentAdapter(variants: ["checkout-flow": ["control", "one-page"], "onboarding": ["control", "video"]])
        adapter.forced["onboarding"] = "video"
        let sut = DebugDrawerExperimentOverrides(adapter: adapter, defaults: defaults)
        let expected = ["onboarding": "video"]

        sut.perform(.setOverride(experiment: "checkout-flow", variant: "one-page"))
        sut.perform(.clearOverride(experiment: "onboarding"))
        sut.perform(.clearAllOverrides)

        #expect(adapter.forced == expected)
        #expect(sut.snapshot.overriddenKeys.isEmpty)
        #expect(!sut.isExcludedFromAnalytics)
    }

    @Test("Whether the device is excluded from analytics is readable off the main actor, as an analytics queue reads it")
    func exclusionReadableOffMainActor() async throws {
        let suite = "ExperimentOverridesTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let adapter = FakeExperimentAdapter(variants: ["checkout-flow": ["control", "one-page"]])
        let sut = DebugDrawerExperimentOverrides(adapter: adapter, defaults: defaults)
        sut.perform(.setOverride(experiment: "checkout-flow", variant: "one-page"))
        let expected = ["checkout-flow"]

        let actual = await Task.detached { (keys: sut.overriddenExperiments, isExcluded: sut.isExcludedFromAnalytics) }.value

        #expect(actual.keys == expected)
        #expect(actual.isExcluded)
    }
}
