#if DEBUG && os(macOS)
    import DebugDrawer
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    /// Where the app's handlers put it, read back by the tests.
    @MainActor
    private final class FakeRouter {
        private(set) var visits: [String] = []

        var scenarios: [DebugDrawerScenario] {
            [
                DebugDrawerScenario("open-order", title: "Open Order", summary: "The order's detail screen", parameters: [
                    .integer("orderID", title: "Order", default: 123, in: 1 ... 999_999),
                    .boolean("showReceipt", title: "Show Receipt", default: true)
                ]) { [unowned self] arguments in
                    visits.append("order \(arguments.integer("orderID") ?? -1) receipt \(arguments.boolean("showReceipt") ?? false)")
                },
                DebugDrawerScenario("show-paywall", title: "Show Paywall", parameters: [
                    .choice("plan", title: "Plan", options: ["monthly", "annual"], default: "annual")
                ]) { [unowned self] arguments in
                    visits.append("paywall \(arguments.string("plan") ?? "?")")
                }
            ]
        }
    }

    // A scenario from the production app's receiver to the sidecar's Launch: the kit lists the app,
    // shows its scenarios through the Scenarios plugin over the store, and Launch leaves the launch
    // in the store, where the receiver performs it in the session and runs the host's handler. Each
    // wait is for the snapshot that step should produce, never for time. Bringing the app forward
    // isn't exercised here (it would open an app on the Mac running the tests); without an app in
    // the environment the plugin says to open the app.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarScenariosTests {
        @Test("The kit lists the app's scenarios, and Launch runs the host's handler with the form's values in the session")
        func launchRunsHandler() async throws {
            let store = FileManager.default.temporaryDirectory
                .appending(path: "SidecarScenariosTests-\(UUID().uuidString)")
                .appending(path: "DebugDrawer")
            let router = FakeRouter()
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let model = DebugDrawerScenarios(scenarios: router.scenarios, launchURL: URL(string: "shop-internal://"))
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.scenarios(model))
            try receiver.start()
            defer { receiver.stop() }
            sessions.perform(.open(duration: 60))
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let sut = try DebugDrawerSidecarConnection(app: listed)
            defer { sut.close() }
            let hosted = try await sut.host(.scenarios)
            let expectedVisits = ["order 123 receipt true"]

            try hosted.body.inspect().find(button: "Launch").tap()

            for await snapshot in model.$snapshot.values where snapshot.lastRun != nil {
                break
            }
            #expect(listed.serves(DebugDrawerScenarios.pluginID))
            #expect(throws: Never.self) { try hosted.body.inspect().find(text: "Open Order") }
            #expect(throws: Never.self) { try hosted.body.inspect().find(text: "The order's detail screen") }
            #expect(throws: Never.self) { try hosted.body.inspect().find(text: "Show Paywall") }
            #expect(router.visits == expectedVisits)
            #expect(model.snapshot.lastRun?.scenario == "open-order")
            #expect(sessions.auditLog.last?.event == .commandApplied)
        }

        @Test("A form starts at each parameter's defaults and gives a value for every parameter")
        func draftStartsAtDefaults() {
            let entry = DebugDrawerScenarios.Entry(id: "s", title: "S", summary: "", parameters: [
                .integer("id", default: 7, in: 1 ... 9), .string("note", default: "hi"), .boolean("on", default: true),
                .choice("plan", options: ["a", "b"], default: "b")
            ])
            let expected: [String: DebugDrawerScenarioValue] = ["id": .integer(7), "note": .string("hi"), "on": .boolean(true), "plan": .string("b")]

            let actual = ScenarioDraft(entry).arguments(for: entry)

            #expect(actual == expected)
        }

        @Test("A form holds no launch while a field's value isn't one its parameter takes; an integer's spaces are trimmed")
        func draftChecksValues() {
            let entry = DebugDrawerScenarios.Entry(id: "s", title: "S", summary: "", parameters: [
                .integer("id", default: 1, in: 1 ... 9), .string("code", maximumLength: 3)
            ])
            var sut = ScenarioDraft(entry)

            sut.texts["id"] = "4.2"
            let fraction = sut.arguments(for: entry)
            sut.texts["id"] = "10"
            let outOfRange = sut.arguments(for: entry)
            sut.texts["id"] = ""
            let empty = sut.arguments(for: entry)
            sut.texts["id"] = " 9 "
            sut.texts["code"] = "ABCD"
            let tooLong = sut.arguments(for: entry)
            sut.texts["code"] = "ABC"
            let valid = sut.arguments(for: entry)

            #expect(fraction == nil)
            #expect(outOfRange == nil)
            #expect(empty == nil)
            #expect(tooLong == nil)
            #expect(valid == ["id": .integer(9), "code": .string("ABC")])
        }

        @Test("Launch hands the section's action the form's values")
        func sectionLaunches() throws {
            let entry = DebugDrawerScenarios.Entry(id: "step", title: "Onboarding Step", summary: "Jumps to a step", parameters: [
                .integer("step", default: 3, in: 1 ... 5)
            ])
            var launched: [[String: DebugDrawerScenarioValue]] = []
            let sut = ScenarioSection(entry: entry) { launched.append($0) }

            try sut.inspect().find(button: "Launch").tap()

            #expect(launched == [["step": .integer(3)]])
            #expect(throws: Never.self) { try sut.inspect().find(text: "Jumps to a step") }
        }

        @Test("With no scenario registered, the plugin says so")
        func noScenarios() throws {
            let sut = ScenariosPlugin(transport: .direct(to: DebugDrawerScenarios(scenarios: [])))

            #expect(throws: Never.self) { try sut.body.inspect().find(text: "No Scenarios") }
        }

        @Test("The last run reads as the scenario's title, its number and time; an unknown ID as itself")
        func lastRunSummary() {
            let snapshot = DebugDrawerScenarios.Snapshot(
                scenarios: [DebugDrawerScenarios.Entry(id: "home", title: "Home", summary: "", parameters: [])], launchURL: nil, lastRun: nil
            )
            let date = Date(timeIntervalSinceReferenceDate: 0)
            let time = date.formatted(date: .omitted, time: .standard)

            let known = DebugDrawerScenarios.Run(number: 2, scenario: "home", date: date).summary(in: snapshot)
            let unknown = DebugDrawerScenarios.Run(number: 1, scenario: "gone", date: date).summary(in: snapshot)

            #expect(known == "Home (#2) at \(time)")
            #expect(unknown == "gone (#1) at \(time)")
        }

        @Test("Opening an app the Mac doesn't have, with no URL, opens nothing and says so")
        func openMissingApp() async {
            let sut = DebugDrawerSidecarApp(
                bundleIdentifier: "com.example.not-installed.\(UUID().uuidString)", displayName: "Missing", version: "", build: "",
                capabilities: [], protocolVersion: 2, lastSeen: Date(), storeDirectory: FileManager.default.temporaryDirectory
            )

            let actual = await sut.open(url: nil)

            #expect(!actual)
        }

        @Test("The shipped Scenarios plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.scenarios

            #expect([sut.id, sut.title, sut.icon] == [DebugDrawerScenarios.pluginID, "Scenarios", "play.rectangle"])
        }
    }
#endif
