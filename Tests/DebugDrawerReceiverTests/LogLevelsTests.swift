import DebugDrawerReceiver
import Foundation
import Testing

/// A logger the test reads back, with a level of the host's own allowed.
@MainActor
private final class FakeLogLevelAdapter: DebugDrawerLogLevelAdapter {
    let subsystems: [String: [String]]
    var levels: [String: String] = [:]

    init(subsystems: [String: [String]]) {
        self.subsystems = subsystems
    }

    func elevatableSubsystems() -> [DebugDrawerLogSubsystem] {
        subsystems.keys.sorted().map { DebugDrawerLogSubsystem(name: $0, levels: subsystems[$0]!, level: levels[$0] ?? "info") }
    }

    func setLevel(_ level: String, forSubsystem subsystem: String) {
        levels[subsystem] = level
    }

    func resetLevel(forSubsystem subsystem: String) {
        levels[subsystem] = nil
    }
}

// The log levels capability's model, driven directly: what it lets a caller change and what it
// resets.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LogLevelsTests {
    @Test("A raised level reaches the adapter and the snapshot, which lists the subsystem as raised")
    func raisesListedLevel() throws {
        let suite = "LogLevelsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let adapter = FakeLogLevelAdapter(subsystems: ["com.example.checkout": ["info", "debug"]])
        let sut = DebugDrawerLogLevels(adapter: adapter, defaults: defaults)
        let expected = DebugDrawerLogLevels.Snapshot(
            subsystems: [DebugDrawerLogSubsystem(name: "com.example.checkout", levels: ["info", "debug"], level: "debug")],
            raisedSubsystems: ["com.example.checkout"]
        )

        sut.perform(.setLevel(subsystem: "com.example.checkout", level: "debug"))

        #expect(sut.snapshot == expected)
    }

    @Test("Performed directly, an unlisted subsystem or a level the subsystem doesn't list changes nothing")
    func ignoresUnlistedSubsystemAndLevel() throws {
        let suite = "LogLevelsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let adapter = FakeLogLevelAdapter(subsystems: ["com.example.checkout": ["info", "debug"]])
        let sut = DebugDrawerLogLevels(adapter: adapter, defaults: defaults)
        let expected = sut.snapshot

        sut.perform(.setLevel(subsystem: "com.example.payments", level: "debug"))
        sut.perform(.setLevel(subsystem: "com.example.checkout", level: "trace"))

        #expect(adapter.levels.isEmpty)
        #expect(sut.snapshot == expected)
    }

    @Test("Resetting puts back only the subsystems the model raised, never a level the host set itself")
    func resetsOnlyItsOwn() throws {
        let suite = "LogLevelsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let adapter = FakeLogLevelAdapter(subsystems: ["com.example.checkout": ["info", "debug"], "com.example.sync": ["info", "debug"]])
        adapter.levels["com.example.sync"] = "debug"
        let sut = DebugDrawerLogLevels(adapter: adapter, defaults: defaults)
        let expected = ["com.example.sync": "debug"]

        sut.perform(.setLevel(subsystem: "com.example.checkout", level: "debug"))
        sut.perform(.reset(subsystem: "com.example.sync"))
        sut.perform(.resetAll)

        #expect(adapter.levels == expected)
        #expect(sut.snapshot.raisedSubsystems.isEmpty)
    }

    @Test("The raised subsystems are kept in the defaults, without their levels, so a relaunched model still lists them")
    func raisedSubsystemsSurviveRelaunch() throws {
        let suite = "LogLevelsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let adapter = FakeLogLevelAdapter(subsystems: ["com.example.checkout": ["info", "debug"], "com.example.sync": ["info", "debug"]])
        DebugDrawerLogLevels(adapter: adapter, defaults: defaults).perform(.setLevel(subsystem: "com.example.sync", level: "debug"))
        let expected = ["com.example.sync"]

        let sut = DebugDrawerLogLevels(adapter: adapter, defaults: defaults)

        #expect(sut.snapshot.raisedSubsystems == expected)
        #expect(defaults.stringArray(forKey: "DebugDrawer.LogLevels.raisedSubsystems") == expected)
    }
}
