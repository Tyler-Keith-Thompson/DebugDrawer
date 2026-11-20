// The state is read as each session opens, on each refresh and for each bug report, on the main
// actor, so it must stay cheap for a large host: hundreds of flags and experiments, many values,
// and the user ID hashed each time.
import DebugDrawerAppInfo
import DebugDrawerReceiver
import Foundation
import Testing

/// A flag service listing `count` flags.
@MainActor
private final class ManyFlags: DebugDrawerFeatureFlagAdapter {
    let count: Int

    init(count: Int) {
        self.count = count
    }

    func overridableFlags() -> [DebugDrawerFeatureFlag] {
        (0 ..< count).map { DebugDrawerFeatureFlag(key: "flag-\($0)", value: .bool(false)) }
    }

    func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {}

    func clearOverride(forKey key: String) {}
}

/// An experiment service listing `count` experiments.
@MainActor
private final class ManyExperiments: DebugDrawerExperimentAdapter {
    let count: Int

    init(count: Int) {
        self.count = count
    }

    func overridableExperiments() -> [DebugDrawerExperiment] {
        (0 ..< count).map { DebugDrawerExperiment(key: "experiment-\($0)", variants: ["a", "b"], assignedVariant: "a") }
    }

    func setOverride(variant: String, forExperiment key: String) {}

    func clearOverride(forExperiment key: String) {}

    func overriddenExperimentsDidChange(_ keys: [String]) {}
}

@MainActor
@Suite
struct AppStateSpeedTests {
    @Test("Reading 500 flags, 500 experiments, 200 values and a hashed user ID takes under 50 ms")
    func largeHost() throws {
        let suite = "AppStateSpeedTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let fields = (0 ..< 200).map { index in DebugDrawerAppStateField("value-\(index)") { .number(Double(index)) } }
        let sut = DebugDrawerAppState(
            sessions: DebugDrawerSessions(maximumDuration: 60),
            featureFlags: DebugDrawerFeatureFlagOverrides(adapter: ManyFlags(count: 500), defaults: defaults),
            experiments: DebugDrawerExperimentOverrides(adapter: ManyExperiments(count: 500), defaults: defaults),
            userID: { "user-1" },
            values: fields,
            defaults: defaults
        )
        let clock = ContinuousClock()

        var actual: DebugDrawerAppState.State?
        let elapsed = clock.measure {
            actual = sut.read()
        }

        #expect(actual?.experiments?.count == 500)
        #expect(actual?.values?.count == 200)
        #expect(elapsed < .milliseconds(50))
    }
}
