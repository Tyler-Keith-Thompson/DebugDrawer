#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    /// The app's sign-in as its handlers change it, read back by the tests.
    @MainActor
    private final class FakeSignIn {
        private(set) var state = "Signed in"

        var actions: [DebugDrawerAuthAction] {
            [
                .expireAccessToken { [weak self] in
                    self?.state = "Expired"
                    return .succeeded
                },
                .logOut { [weak self] in
                    self?.state = "Signed out"
                    return .succeeded
                }
            ]
        }
    }

    // An auth action from the production app's receiver to the sidecar's button: the kit lists the
    // app, shows its actions through the Auth plugin over the store, and a button leaves the
    // request in the store, where the receiver performs it in the session and runs the host's
    // handler, whose outcome comes back. Each wait is for the snapshot that step should produce,
    // never for time. Bringing the app forward isn't exercised here (it would open an app on the
    // Mac running the tests); without an app in the environment the plugin says to open the app.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarAuthActionsTests {
        @Test("The kit lists the app's auth actions, and a button runs the host's handler in the session; its result comes back")
        func buttonRunsHandler() async throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarAuthActionsTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let signIn = FakeSignIn()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let model = try DebugDrawerAuthActions(actions: signIn.actions, launchURL: URL(string: "shop-internal://"))
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.authActions(model))
            try receiver.start()
            defer { receiver.stop() }
            sessions.perform(.open(duration: 60))
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let sut = try DebugDrawerSidecarConnection(app: listed)
            defer { sut.close() }
            let hosted = try await sut.host(.authActions)

            try hosted.body.inspect().find(button: "Log Out").tap()

            for await snapshot in model.$snapshot.values where snapshot.actions[1].lastRun?.status == .succeeded {
                break
            }
            #expect(listed.serves(DebugDrawerAuthActions.pluginID))
            #expect(throws: Never.self) { try hosted.body.inspect().find(text: "The next request meets an expired token") }
            #expect(throws: Never.self) { try hosted.body.inspect().find(button: "Expire Access Token") }
            #expect(signIn.state == "Signed out")
            #expect(model.snapshot.actions[0].lastRun == nil)
            #expect(sessions.auditLog.last?.event == .commandApplied)
        }

        @Test("An action's button hands the section's request action; its last run is shown")
        func sectionRequests() throws {
            let started = Date(timeIntervalSinceReferenceDate: 0)
            let run = DebugDrawerAuthActions.Run(number: 3, started: started, status: .failed(message: "Not signed in"))
            let entry = DebugDrawerAuthActions.Entry(
                id: "force-refresh", title: "Force Token Refresh", summary: "Refreshes the tokens now", lastRun: run
            )
            var requests = 0
            let sut = AuthActionSection(entry: entry) { requests += 1 }

            try sut.inspect().find(button: "Force Token Refresh").tap()

            #expect(requests == 1)
            #expect(throws: Never.self) { try sut.inspect().find(text: "Refreshes the tokens now") }
            #expect(throws: Never.self) { try sut.inspect().find(text: run.summary) }
        }

        @Test("A run reads as its status, with a failure's message, its number and time")
        func runSummary() {
            let date = Date(timeIntervalSinceReferenceDate: 0)
            let time = date.formatted(date: .omitted, time: .standard)

            let actual = [
                DebugDrawerAuthActions.Run(number: 1, started: date, status: .running),
                DebugDrawerAuthActions.Run(number: 2, started: date, status: .succeeded),
                DebugDrawerAuthActions.Run(number: 3, started: date, status: .failed(message: "Not signed in"))
            ].map(\.summary)

            #expect(actual == ["Running (#1, \(time))", "Succeeded (#2, \(time))", "Failed: Not signed in (#3, \(time))"])
        }

        @Test("With no action registered, the plugin says so")
        func noActions() throws {
            let sut = try AuthActionsPlugin(transport: .direct(to: DebugDrawerAuthActions(actions: [])))

            #expect(throws: Never.self) { try sut.body.inspect().find(text: "No Auth Actions") }
        }

        @Test("The shipped Auth plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.authActions

            #expect([sut.id, sut.title, sut.icon] == [DebugDrawerAuthActions.pluginID, "Auth", "person.badge.key"])
        }
    }
#endif
