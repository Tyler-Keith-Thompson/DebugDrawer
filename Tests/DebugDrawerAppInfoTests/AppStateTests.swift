// The app state capability's model, driven directly over the receiver's sessions: what it serves,
// when, and from which of the host's sources.
import CryptoKit
@testable import DebugDrawerAppInfo
import DebugDrawerReceiver
import Foundation
import Testing

/// How many times the host's closure was asked.
@MainActor
private final class ReadCount {
    var count = 0
}

/// A cart whose item count the test changes.
@MainActor
private final class Cart {
    var items = 1.0
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct AppStateTests {
    @Test("With nothing registered, the state holds only the standard fields: bundle, version, build, build metadata and date")
    func emptyRegistrationHoldsStandardFieldsOnly() throws {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = DebugDrawerAppState(sessions: sessions, defaults: defaults)
        let expected: Set<String> = ["bundleIdentifier", "version", "build", "buildMetadata", "date"]

        sessions.perform(.open(duration: 60))

        let state = try #require(sut.snapshot.state)
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(state)) as? [String: Any])
        #expect(Set(json.keys) == expected)
        #expect(state.featureFlagOverrides == nil)
        #expect(state.experiments == nil)
        #expect(state.environment == nil)
        #expect(state.hashedUserID == nil)
        #expect(state.values == nil)
        #expect(defaults.data(forKey: UserIDHasher.keyDefaultsKey) == nil)
    }

    @Test("The standard fields come from the bundle's Info.plist, a passed build metadata value winning over its key")
    func standardFieldsFromBundle() throws {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.shop",
            "CFBundleShortVersionString": "2.4.0",
            "CFBundleVersion": "881",
            "DebugDrawerGitCommit": "plist-sha",
            "DebugDrawerGitBranch": "release/2.4",
            "DebugDrawerCIBuildNumber": "1042"
        ]
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).bundle", directoryHint: .isDirectory)
        #if os(macOS)
            let contents = url.appending(path: "Contents", directoryHint: .isDirectory)
        #else
            let contents = url
        #endif
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appending(path: "Info.plist"))
        let bundle = try #require(Bundle(url: url))
        let read = Date(timeIntervalSince1970: 1_800_000_000)
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = DebugDrawerAppState(
            sessions: sessions, bundle: bundle, buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1"),
            featureFlags: nil, experiments: nil, environments: nil, userID: nil, values: [], defaults: defaults, now: { read }
        )
        let expected = DebugDrawerAppState.State(
            bundleIdentifier: "com.example.shop", version: "2.4.0", build: "881",
            buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1", gitBranch: "release/2.4", ciBuildNumber: "1042"), date: read
        )

        let actual = sut.read()

        #expect(actual == expected)
    }

    @Test("Outside a session nothing is served and nothing is read; the state comes as one opens and goes as it ends")
    func servedDuringSessionOnly() throws {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let reads = ReadCount()
        let sut = DebugDrawerAppState(
            sessions: sessions,
            userID: {
                reads.count += 1
                return "user-1"
            },
            defaults: defaults
        )
        let empty = DebugDrawerAppState.Snapshot(sessionID: nil, state: nil)

        let before = sut.snapshot
        let readsBefore = reads.count
        sessions.perform(.open(duration: 60))
        let opened = sessions.snapshot.session?.id
        let during = sut.snapshot
        sessions.end()
        let after = sut.snapshot

        #expect(before == empty)
        #expect(readsBefore == 0)
        #expect(opened != nil)
        #expect(during.sessionID == opened)
        #expect(during.state?.hashedUserID != nil)
        #expect(after == empty)
    }

    @Test("Registered sources appear: overridden flags only, every experiment's bucket, the active environment, the hashed ID and the values")
    func registeredSourcesAppear() throws {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let flagService = FakeFlagService(["new-checkout": .bool(false), "button-color": .string("blue")])
        let flags = DebugDrawerFeatureFlagOverrides(adapter: flagService, defaults: defaults)
        flags.perform(.setOverride(key: "new-checkout", value: .bool(true)))
        let experimentService = FakeExperimentService(
            variants: ["checkout-flow": ["control", "one-page"], "onboarding": ["a", "b"]], assigned: ["checkout-flow": "control"]
        )
        let experiments = DebugDrawerExperimentOverrides(adapter: experimentService, defaults: defaults)
        experiments.perform(.setOverride(experiment: "onboarding", variant: "b"))
        let environments = DebugDrawerEnvironments(
            default: DebugDrawerEnvironment("production", title: "Production"),
            allowing: DebugDrawerEnvironment("staging", title: "Staging"),
            adapter: FakeBackend(), defaults: defaults
        )
        let sut = DebugDrawerAppState(
            sessions: sessions, featureFlags: flags, experiments: experiments, environments: environments,
            userID: { "user-8271" },
            values: [
                DebugDrawerAppStateField("plan") { "pro" },
                DebugDrawerAppStateField("cartItems") { 3 },
                DebugDrawerAppStateField("darkMode") { true },
                DebugDrawerAppStateField("coupon") { nil }
            ],
            defaults: defaults
        )
        let expectedFlags: [String: DebugDrawerFeatureFlagValue] = ["new-checkout": .bool(true)]
        let expectedExperiments: [String: DebugDrawerAppState.ExperimentBucket] = [
            "checkout-flow": .init(variant: "control", isOverridden: false),
            "onboarding": .init(variant: "b", isOverridden: true)
        ]
        let expectedEnvironment = DebugDrawerAppState.ActiveEnvironment(id: "production", title: "Production", isSwitched: false)
        let expectedValues: [String: DebugDrawerAppStateValue] = ["plan": .string("pro"), "cartItems": .number(3), "darkMode": .bool(true)]

        sessions.perform(.open(duration: 60))

        let state = try #require(sut.snapshot.state)
        #expect(state.featureFlagOverrides == expectedFlags)
        #expect(state.experiments == expectedExperiments)
        #expect(state.environment == expectedEnvironment)
        #expect(state.values == expectedValues)
        #expect(state.hashedUserID?.count == 64)
    }

    @Test("A change a sidecar makes to a registered model shows in the state served at once")
    func followsRegisteredModels() throws {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let flags = DebugDrawerFeatureFlagOverrides(adapter: FakeFlagService(["new-checkout": .bool(false)]), defaults: defaults)
        let environments = DebugDrawerEnvironments(
            default: DebugDrawerEnvironment("production", title: "Production"),
            allowing: DebugDrawerEnvironment("staging", title: "Staging"),
            adapter: FakeBackend(), defaults: defaults
        )
        let sut = DebugDrawerAppState(sessions: sessions, featureFlags: flags, environments: environments, defaults: defaults)
        sessions.perform(.open(duration: 60))
        let expectedFlags: [String: DebugDrawerFeatureFlagValue] = ["new-checkout": .bool(true)]
        let expectedEnvironment = DebugDrawerAppState.ActiveEnvironment(id: "staging", title: "Staging", isSwitched: true)

        flags.perform(.setOverride(key: "new-checkout", value: .bool(true)))
        environments.perform(.activate(environment: "staging"))

        #expect(sut.snapshot.state?.featureFlagOverrides == expectedFlags)
        #expect(sut.snapshot.state?.environment == expectedEnvironment)
        environments.perform(.reset)
    }

    @Test("Refresh reads the host's values and the user ID again; outside a session it serves nothing")
    func refreshRereads() throws {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let cart = Cart()
        let sut = DebugDrawerAppState(
            sessions: sessions, values: [DebugDrawerAppStateField("cartItems") { .number(cart.items) }], defaults: defaults
        )
        let expected: [String: DebugDrawerAppStateValue] = ["cartItems": .number(4)]
        sut.perform(.refresh)
        let outside = sut.snapshot
        sessions.perform(.open(duration: 60))
        cart.items = 4

        sut.perform(.refresh)

        #expect(outside.state == nil)
        #expect(sut.snapshot.state?.values == expected)
    }

    @Test("The user ID is HMAC-SHA256 under the install's key: stable across models of one install, other on another install")
    func hashIsStablePerInstall() throws {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let otherSuite = "AppStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let otherInstall = try #require(UserDefaults(suiteName: otherSuite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            otherInstall.removePersistentDomain(forName: otherSuite)
        }
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let rawID = "user-8271"
        let first = DebugDrawerAppState(sessions: sessions, userID: { rawID }, defaults: defaults).read().hashedUserID
        let relaunched = DebugDrawerAppState(sessions: sessions, userID: { rawID }, defaults: defaults).read().hashedUserID
        let elsewhere = DebugDrawerAppState(sessions: sessions, userID: { rawID }, defaults: otherInstall).read().hashedUserID
        let key = try #require(defaults.data(forKey: UserIDHasher.keyDefaultsKey))
        let expected = HMAC<SHA256>.authenticationCode(for: Data(rawID.utf8), using: SymmetricKey(data: key))
            .map { String(format: "%02x", $0) }.joined()
        let unkeyed = SHA256.hash(data: Data(rawID.utf8)).map { String(format: "%02x", $0) }.joined()

        #expect(first == expected)
        #expect(relaunched == first)
        #expect(elsewhere != first)
        #expect(first != unkeyed)
        #expect(key.count == 32)
    }

    @Test("No one signed in: the user ID reads nil and no hash is served")
    func signedOut() throws {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let sut = DebugDrawerAppState(sessions: sessions, userID: { nil }, defaults: defaults)

        let actual = sut.read()

        #expect(actual.hashedUserID == nil)
    }

    @Test("Under a grant policy, a session whose grant doesn't list the capability is served nothing")
    func grantWithoutCapability() throws {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let policy = DebugDrawerGrantPolicy(
            verifier: AcceptingGrantVerifier(audience: "com.example.shop", capabilities: ["DebugDrawer.Environments"]),
            audience: "com.example.shop"
        )
        let sessions = DebugDrawerSessions(maximumDuration: 300, grantPolicy: policy)
        let sut = DebugDrawerAppState(sessions: sessions, userID: { "user-1" }, defaults: defaults)

        sessions.perform(.open(duration: 60, grant: "grant-1"))

        #expect(sessions.snapshot.isActive)
        #expect(sut.snapshot.sessionID != nil)
        #expect(sut.snapshot.state == nil)
    }

    @Test("Under a grant policy, a session whose grant lists the capability is served the state")
    func grantWithCapability() throws {
        let suite = "AppStateTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let policy = DebugDrawerGrantPolicy(
            verifier: AcceptingGrantVerifier(audience: "com.example.shop", capabilities: [DebugDrawerAppState.pluginID]),
            audience: "com.example.shop"
        )
        let sessions = DebugDrawerSessions(maximumDuration: 300, grantPolicy: policy)
        let sut = DebugDrawerAppState(sessions: sessions, defaults: defaults)

        sessions.perform(.open(duration: 60, grant: "grant-2"))

        #expect(sut.snapshot.state != nil)
    }

    @Test("A host value encodes as the bare JSON value and decodes back to its case")
    func valueCoding() throws {
        let values: [String: DebugDrawerAppStateValue] = ["plan": "pro", "seats": 3, "ratio": 0.5, "beta": false]
        let expected = #"{"beta":false,"plan":"pro","ratio":0.5,"seats":3}"#
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        let json = try encoder.encode(values)
        let decoded = try JSONDecoder().decode([String: DebugDrawerAppStateValue].self, from: json)

        #expect(String(bytes: json, encoding: .utf8) == expected)
        #expect(decoded == values)
    }
}
