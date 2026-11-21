@testable import DebugDrawerReceiver
import DebugDrawerTestSupport
import Foundation
import Testing

/// The host's backend switch: every environment it was told to activate, and the record the model
/// had kept in the defaults at that moment.
@MainActor
private final class RecordingBackend: DebugDrawerEnvironmentAdapter {
    let defaults: UserDefaults
    private(set) var activated: [DebugDrawerEnvironment] = []
    private(set) var recordWhenActivated: [String?] = []

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    func activate(_ environment: DebugDrawerEnvironment) {
        activated.append(environment)
        recordWhenActivated.append(defaults.string(forKey: DebugDrawerEnvironments.activeEnvironmentDefaultsKey))
    }
}

// The environments' model on its own: what it lists, the wire format a sidecar reads and sends
// (which has no field a URL could travel in), which commands it refuses, and what it records.
@MainActor
struct EnvironmentsTests {
    private let production = DebugDrawerEnvironment("production", title: "Production")
    private let staging = DebugDrawerEnvironment("staging", title: "Staging", summary: "Yesterday's server build")
    private let canary = DebugDrawerEnvironment("canary", title: "Canary")

    @Test("An environment holds an ID, a title and a summary, and nothing else: no URL can be given to it")
    func environmentHoldsNoURL() {
        let sut = DebugDrawerEnvironment("staging", title: "Staging", summary: "Yesterday's server build")

        let actual = Mirror(reflecting: sut).children.map(\.label)

        #expect(actual == ["id", "title", "summary"])
    }

    @Test("The snapshot's JSON has the environments' IDs, titles and summaries and the default and active IDs, and no other key")
    func snapshotSchema() throws {
        let suite = temporarySuiteName("EnvironmentsTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = RecordingBackend(defaults: defaults)
        let sut = DebugDrawerEnvironments(default: production, allowing: staging, canary, adapter: backend, defaults: defaults)
        let expectedTopLevel: Set<String> = ["environments", "defaultEnvironment", "activeEnvironment"]
        let expectedEnvironment: Set<String> = ["id", "title", "summary"]

        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(sut.snapshot)) as? [String: Any])

        let environments = try #require(object["environments"] as? [[String: Any]])
        #expect(Set(object.keys) == expectedTopLevel)
        #expect(environments.count == 3)
        #expect(environments.allSatisfy { Set($0.keys) == expectedEnvironment })
        #expect(sut.snapshot.environments == [production, staging, canary])
    }

    @Test("A command's JSON carries an environment's ID and nothing else")
    func commandSchema() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let actual = try [
            DebugDrawerEnvironments.Command.activate(environment: "staging"),
            DebugDrawerEnvironments.Command.reset
        ].map { try #require(String(bytes: encoder.encode($0), encoding: .utf8)) }

        #expect(actual == [#"{"activate":{"environment":"staging"}}"#, #"{"reset":{}}"#])
    }

    @Test("An environment the host didn't list is refused notExposed, the default and allowed ones and reset are not")
    func refusals() throws {
        let suite = temporarySuiteName("EnvironmentsTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sut = DebugDrawerEnvironments(default: production, allowing: staging, adapter: RecordingBackend(defaults: defaults), defaults: defaults)
        let commands: [DebugDrawerEnvironments.Command] = [
            .activate(environment: "production"),
            .activate(environment: "staging"),
            .activate(environment: "canary"),
            .activate(environment: "https://staging.api.example.com"),
            .activate(environment: ""),
            .reset
        ]

        let actual = commands.map(sut.refusal(of:))

        #expect(actual == [nil, nil, .notExposed, .notExposed, .notExposed, nil])
    }

    @Test("A switch is recorded before the adapter is told, and the record is removed as the default comes back")
    func recordPrecedesSwitch() throws {
        let suite = temporarySuiteName("EnvironmentsTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = RecordingBackend(defaults: defaults)
        let sut = DebugDrawerEnvironments(default: production, allowing: staging, canary, adapter: backend, defaults: defaults)

        sut.perform(.activate(environment: "staging"))
        sut.perform(.activate(environment: "canary"))
        sut.perform(.reset)

        #expect(backend.activated == [staging, canary, production])
        #expect(backend.recordWhenActivated == ["staging", "canary", "canary"])
        #expect(defaults.string(forKey: DebugDrawerEnvironments.activeEnvironmentDefaultsKey) == nil)
        #expect(!sut.snapshot.isSwitched)
    }

    @Test("Activating the active environment, or resetting while on the default, tells the adapter nothing")
    func noRepeatedSwitch() throws {
        let suite = temporarySuiteName("EnvironmentsTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = RecordingBackend(defaults: defaults)
        let sut = DebugDrawerEnvironments(default: production, allowing: staging, adapter: backend, defaults: defaults)

        sut.perform(.reset)
        sut.perform(.activate(environment: "production"))
        sut.perform(.activate(environment: "staging"))
        sut.perform(.activate(environment: "staging"))

        #expect(backend.activated == [staging])
        #expect(sut.snapshot.activeEnvironment == "staging")
        #expect(sut.snapshot.isSwitched)
    }

    @Test("Performed directly, an environment the host didn't list changes nothing")
    func unlistedIgnored() throws {
        let suite = temporarySuiteName("EnvironmentsTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = RecordingBackend(defaults: defaults)
        let sut = DebugDrawerEnvironments(default: production, allowing: staging, adapter: backend, defaults: defaults)

        sut.perform(.activate(environment: "https://attacker.example"))

        #expect(backend.activated.isEmpty)
        #expect(sut.snapshot.activeEnvironment == "production")
        #expect(defaults.string(forKey: DebugDrawerEnvironments.activeEnvironmentDefaultsKey) == nil)
    }

    @Test("A record naming an environment the app no longer lists is still undone as the capability is made")
    func staleRecordUndone() throws {
        let suite = temporarySuiteName("EnvironmentsTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("retired-qa", forKey: DebugDrawerEnvironments.activeEnvironmentDefaultsKey)
        let backend = RecordingBackend(defaults: defaults)
        let model = DebugDrawerEnvironments(default: production, allowing: staging, adapter: backend, defaults: defaults)

        let sut = DebugDrawerReceiverCapability.environments(model)

        #expect(sut.id == DebugDrawerEnvironments.pluginID)
        #expect(backend.activated == [production])
        #expect(model.snapshot.activeEnvironment == "production")
        #expect(defaults.string(forKey: DebugDrawerEnvironments.activeEnvironmentDefaultsKey) == nil)
    }
}
