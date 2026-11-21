#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    /// The app's flag service, read back by the tests.
    @MainActor
    private final class FakeFlagService: DebugDrawerFeatureFlagAdapter {
        private(set) var overrides: [String: DebugDrawerFeatureFlagValue] = [:]

        func overridableFlags() -> [DebugDrawerFeatureFlag] {
            [
                DebugDrawerFeatureFlag(key: "new-checkout", value: overrides["new-checkout"] ?? .bool(false)),
                DebugDrawerFeatureFlag(key: "button-color", value: overrides["button-color"] ?? .string("blue"))
            ]
        }

        func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
            overrides[key] = value
        }

        func clearOverride(forKey key: String) {
            overrides[key] = nil
        }
    }

    // An override from the sidecar's switch to the production app's receiver: the kit lists the
    // app, shows its flags through the Flags plugin over the store, and the switch leaves the
    // override in the store, where the receiver performs it in the session and the host's adapter
    // gets it. Each wait is for the snapshot that step should produce, never for time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarFeatureFlagOverridesTests {
        private let checkout = DebugDrawerFeatureFlag(key: "new-checkout", value: .bool(false))
        private let color = DebugDrawerFeatureFlag(key: "button-color", value: .string("blue"))
        private let ratio = DebugDrawerFeatureFlag(key: "sample-ratio", value: .number(0.25))

        @Test("The kit lists the app's flags, and the switch overrides the flag in the host's service in the session")
        func switchOverridesTheFlag() async throws {
            let suite = "SidecarFeatureFlagOverridesTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarFeatureFlagOverridesTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let service = FakeFlagService()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let model = DebugDrawerFeatureFlagOverrides(adapter: service, defaults: defaults)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.featureFlagOverrides(model))
            try receiver.start()
            defer { receiver.stop() }
            sessions.perform(.open(duration: 60))
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let sut = try DebugDrawerSidecarConnection(app: listed)
            defer { sut.close() }
            let hosted = try await sut.host(.featureFlagOverrides)

            try hosted.body.inspect().find(viewWithAccessibilityIdentifier: "Flag-new-checkout").find(ViewType.Toggle.self).tap()

            for await snapshot in model.$snapshot.values where snapshot.overriddenKeys == ["new-checkout"] {
                break
            }
            #expect(listed.serves(DebugDrawerFeatureFlagOverrides.pluginID))
            #expect(service.overrides == ["new-checkout": .bool(true)])
            #expect(sessions.auditLog.last?.event == .commandApplied)
        }

        @Test("A Boolean's switch sends its override; an overridden flag is marked and Clear clears it; Clear All Overrides clears all")
        func viewSendsOverrides() throws {
            let snapshot = DebugDrawerFeatureFlagOverrides.Snapshot(flags: [checkout, color, ratio], overriddenKeys: ["button-color"])
            var sent: [DebugDrawerFeatureFlagOverrides.Command] = []
            let sut = FeatureFlagOverridesView(snapshot: snapshot) { sent.append($0) }

            try sut.inspect().find(viewWithAccessibilityIdentifier: "Flag-new-checkout").find(ViewType.Toggle.self).tap()
            try sut.inspect().find(viewWithAccessibilityIdentifier: "Flag-button-color").find(button: "Clear").tap()
            try sut.inspect().find(button: "Clear All Overrides").tap()

            #expect(sent == [.setOverride(key: "new-checkout", value: .bool(true)), .clearOverride(key: "button-color"), .clearAllOverrides])
            #expect(throws: Never.self) { try sut.inspect().find(viewWithAccessibilityIdentifier: "Flag-button-color").find(text: "Overridden") }
            #expect(throws: Never.self) { try sut.inspect().find(viewWithAccessibilityIdentifier: "Flag-button-color").find(text: "\"blue\"") }
            #expect(throws: (any Error).self) { try sut.inspect().find(viewWithAccessibilityIdentifier: "Flag-new-checkout").find(button: "Clear") }
        }

        @Test("A field's Set holds back the flag's own value, and sends nothing while it holds it")
        func setIsDisabledForTheCurrentValue() throws {
            let snapshot = DebugDrawerFeatureFlagOverrides.Snapshot(flags: [ratio], overriddenKeys: [])
            var sent: [DebugDrawerFeatureFlagOverrides.Command] = []
            let sut = FeatureFlagOverridesView(snapshot: snapshot) { sent.append($0) }

            let set = try sut.inspect().find(viewWithAccessibilityIdentifier: "Flag-sample-ratio").find(button: "Set")

            #expect(set.isDisabled())
            #expect(throws: (any Error).self) { try set.tap() }
            #expect(sent.isEmpty)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Clear All Overrides") }
        }

        @Test("Field text becomes an override only as a value of the flag's own kind: a finite number for a number, any text for a string")
        func fieldTextBecomesValueOfTheFlagsKind() {
            let number = DebugDrawerFeatureFlagValue.number(1)
            let string = DebugDrawerFeatureFlagValue.string("blue")
            let bool = DebugDrawerFeatureFlagValue.bool(true)

            let actual: [DebugDrawerFeatureFlagValue?] = [
                number.sameKind(from: " 0.5 "), number.sameKind(from: "half"), number.sameKind(from: "inf"),
                string.sameKind(from: "green"), bool.sameKind(from: "true")
            ]

            #expect(actual == [.number(0.5), nil, nil, .string("green"), nil])
        }

        @Test("With no flag listed the plugin says so")
        func noFlags() throws {
            let sut = FeatureFlagOverridesView(snapshot: DebugDrawerFeatureFlagOverrides.Snapshot(flags: [], overriddenKeys: [])) { _ in }

            #expect(throws: Never.self) { try sut.inspect().find(text: "The app's adapter lists no flag a sidecar may override.") }
        }

        @Test("The shipped Flags plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.featureFlagOverrides

            #expect([sut.id, sut.title, sut.icon] == [DebugDrawerFeatureFlagOverrides.pluginID, "Flags", "flag"])
        }
    }
#endif
