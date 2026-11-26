// What the environment allowlist refuses as it is made: what the types can't rule out (an empty
// allowlist doesn't compile, since the default and at least one allowed environment are separate
// parameters). Real in every build, so these run in debug and release alike.
import DebugDrawerReceiver
import DebugDrawerTestSupport
import Foundation
import Testing

/// A backend switch that records nothing, for tests that only make the model.
@MainActor
private final class IdleBackend: DebugDrawerEnvironmentAdapter {
    func activate(_ environment: DebugDrawerEnvironment) {}
}

@MainActor
@Suite
struct EnvironmentsValidationTests {
    @Test("An allowlist whose only environment repeats the default's ID, leaving nothing to switch to, throws duplicateID")
    func allowlistOfOnlyTheDefault() throws {
        let suite = temporarySuiteName("EnvironmentsValidationTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = DebugDrawerEnvironments.InvalidEnvironments.duplicateID

        #expect(throws: expected) {
            _ = try DebugDrawerEnvironments(
                default: DebugDrawerEnvironment("production", title: "Production"),
                allowing: DebugDrawerEnvironment("production", title: "Production Again"),
                adapter: IdleBackend(),
                defaults: defaults
            )
        }
    }

    @Test("Two allowed environments with one ID throw duplicateID")
    func repeatedAllowedID() {
        let expected = DebugDrawerEnvironments.InvalidEnvironments.duplicateID

        #expect(throws: expected) {
            _ = try DebugDrawerReceiverCapability.environments(
                default: DebugDrawerEnvironment("production", title: "Production"),
                allowing: DebugDrawerEnvironment("staging", title: "Staging"),
                DebugDrawerEnvironment("staging", title: "Staging Again"),
                adapter: IdleBackend()
            )
        }
    }

    @Test("An allowed environment with an empty ID throws emptyID")
    func emptyAllowedID() throws {
        let suite = temporarySuiteName("EnvironmentsValidationTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = DebugDrawerEnvironments.InvalidEnvironments.emptyID

        #expect(throws: expected) {
            _ = try DebugDrawerEnvironments(
                default: DebugDrawerEnvironment("production", title: "Production"),
                allowing: DebugDrawerEnvironment("", title: "Nowhere"),
                adapter: IdleBackend(),
                defaults: defaults
            )
        }
    }

    @Test("A default environment with an empty ID throws emptyID")
    func emptyDefaultID() throws {
        let suite = temporarySuiteName("EnvironmentsValidationTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = DebugDrawerEnvironments.InvalidEnvironments.emptyID

        #expect(throws: expected) {
            _ = try DebugDrawerEnvironments(
                default: DebugDrawerEnvironment("", title: "Nowhere"),
                allowing: DebugDrawerEnvironment("staging", title: "Staging"),
                adapter: IdleBackend(),
                defaults: defaults
            )
        }
    }

    @Test("A default and one allowed environment, the smallest allowlist, are taken, the default first")
    func smallestAllowlist() throws {
        let suite = temporarySuiteName("EnvironmentsValidationTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let expected = ["production", "staging"]

        let sut = try DebugDrawerEnvironments(
            default: DebugDrawerEnvironment("production", title: "Production"),
            allowing: DebugDrawerEnvironment("staging", title: "Staging"),
            adapter: IdleBackend(),
            defaults: defaults
        )

        #expect(sut.snapshot.environments.map(\.id) == expected)
        #expect(sut.snapshot.activeEnvironment == "production")
    }
}
