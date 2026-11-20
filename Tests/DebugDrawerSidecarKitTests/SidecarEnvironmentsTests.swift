#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    /// The app's backend switch, read back by the tests; its base URLs never reach the receiver.
    @MainActor
    private final class FakeBackend: DebugDrawerEnvironmentAdapter {
        private(set) var baseURL = "https://api.example.com"

        func activate(_ environment: DebugDrawerEnvironment) {
            baseURL = environment.id == "staging" ? "https://staging.api.example.com" : "https://api.example.com"
        }
    }

    // A switch from the sidecar's button to the production app's receiver: the kit lists the app,
    // shows its environments through the Environment plugin over the store, and Switch leaves the
    // environment's ID in the store, where the receiver performs it in the session and the host's
    // adapter points the app at its own configuration for it. Each wait is for the snapshot that
    // step should produce, never for time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarEnvironmentsTests {
        private let production = DebugDrawerEnvironment("production", title: "Production")
        private let staging = DebugDrawerEnvironment("staging", title: "Staging", summary: "Yesterday's server build")

        @Test("The kit lists the app's environments, and Switch points the app at the host's own configuration for one in the session")
        func switchButtonSwitches() async throws {
            let suite = "SidecarEnvironmentsTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarEnvironmentsTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let backend = FakeBackend()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let model = DebugDrawerEnvironments(default: production, allowing: staging, adapter: backend, defaults: defaults)
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.environments(model))
            try receiver.start()
            defer { receiver.stop() }
            sessions.perform(.open(duration: 60))
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let sut = try DebugDrawerSidecarConnection(app: listed)
            defer { sut.close() }
            let hosted = try await sut.host(.environments)

            try hosted.body.inspect().find(viewWithAccessibilityIdentifier: "Environment-staging").find(button: "Switch").tap()

            for await snapshot in model.$snapshot.values where snapshot.activeEnvironment == "staging" {
                break
            }
            #expect(listed.serves(DebugDrawerEnvironments.pluginID))
            #expect(backend.baseURL == "https://staging.api.example.com")
            #expect(sessions.auditLog.last?.event == .commandApplied)
        }

        @Test("The active environment is marked and has no Switch; another's Switch sends its ID; Reset to Default sends reset")
        func viewSendsIDs() throws {
            let snapshot = DebugDrawerEnvironments.Snapshot(
                environments: [production, staging], defaultEnvironment: "production", activeEnvironment: "staging"
            )
            var sent: [DebugDrawerEnvironments.Command] = []
            let sut = EnvironmentsView(snapshot: snapshot) { sent.append($0) }

            try sut.inspect().find(viewWithAccessibilityIdentifier: "Environment-production").find(button: "Switch").tap()
            try sut.inspect().find(button: "Reset to Default").tap()

            #expect(sent == [.activate(environment: "production"), .reset])
            #expect(throws: Never.self) { try sut.inspect().find(viewWithAccessibilityIdentifier: "Environment-staging").find(text: "Active") }
            #expect(throws: (any Error).self) {
                try sut.inspect().find(viewWithAccessibilityIdentifier: "Environment-staging").find(button: "Switch")
            }
            #expect(throws: Never.self) { try sut.inspect().find(text: "Yesterday's server build") }
        }

        @Test("The plugin flags the risk, and offers no Reset to Default while the app is on its default")
        func riskWarningAndNoResetOnDefault() throws {
            let snapshot = DebugDrawerEnvironments.Snapshot(
                environments: [production, staging], defaultEnvironment: "production", activeEnvironment: "production"
            )
            let sut = EnvironmentsView(snapshot: snapshot) { _ in }

            let warning = try sut.inspect().find(viewWithAccessibilityIdentifier: "EnvironmentsRiskWarning")

            #expect(throws: Never.self) { try warning.find(ViewType.Text.self, where: { try $0.string().contains("until the session ends") }) }
            #expect(throws: Never.self) { try sut.inspect().find(text: "High Risk") }
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Reset to Default") }
        }

        @Test("The shipped Environment plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.environments

            #expect([sut.id, sut.title, sut.icon] == [DebugDrawerEnvironments.pluginID, "Environment", "server.rack"])
        }
    }
#endif
