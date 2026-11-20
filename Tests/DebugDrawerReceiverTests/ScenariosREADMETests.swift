// The README's "Scenarios: launching the app into a state" example, verbatim, so the README cannot
// drift from the code: the app's router and its scenarios, launched as a sidecar's commands are,
// from the store.
@testable import DebugDrawerReceiver
import Foundation
import Testing

@MainActor
final class ShopRouter {
    private(set) var screen = "Home"

    func openOrder(_ id: Int) { screen = "Order \(id)" }
    func showPaywall(plan: String) { screen = "Paywall (\(plan))" }
}

@MainActor
private final class ProductionScenarios {
    let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
    let receiver: DebugDrawerReceiver

    init(router: ShopRouter, container: URL) throws {
        receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
        receiver.enable(.scenarios([
            DebugDrawerScenario("open-order", title: "Open Order", parameters: [
                .integer("orderID", title: "Order", default: 123, in: 1 ... 999_999)
            ]) { arguments in
                router.openOrder(arguments.integer("orderID") ?? 123)
            },
            DebugDrawerScenario("show-paywall", title: "Show Paywall", parameters: [
                .choice("plan", title: "Plan", options: ["monthly", "annual"])
            ]) { arguments in
                router.showPaywall(plan: arguments.string("plan") ?? "monthly")
            }
        ], launchURL: URL(string: "shop-internal://")))
        try receiver.start()
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ScenariosREADMETests {
    @Test("README: a launch left in the store runs the scenario's handler with its parameter in a session")
    func readmeScenarios() throws {
        let container = FileManager.default.temporaryDirectory.appending(path: "READMEScenarios-\(UUID().uuidString)")
        let router = ShopRouter()
        let app = try ProductionScenarios(router: router, container: container)
        defer { app.receiver.stop() }
        app.sessions.perform(.open(duration: 60))
        let layout = AppGroupStoreLayout(directory: app.receiver.appDirectory)
        let payload = try TransportMessage.payload(DebugDrawerScenarios.Command.run(scenario: "open-order", arguments: ["orderID": .integer(42)]))
        let document = StoreDocument(TransportMessage(kind: .command, pluginID: DebugDrawerScenarios.pluginID, payload: payload))
        try layout.write(document.encoded(), to: layout.commands.appending(path: "0.json"))

        app.receiver.reevaluateGates()

        #expect(router.screen == "Order 42")
    }
}
