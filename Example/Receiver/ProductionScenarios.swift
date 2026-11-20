import Combine
import DebugDrawerReceiver
import Foundation

/// The example's router: the screen a scenario puts the app on, which the host shows as a sheet.
/// A sidecar launches it there through the scenarios capability; the handlers are the app's own
/// code and read only the parameters each scenario declares.
@MainActor
final class ProductionScenarios: ObservableObject {
    /// A screen deep in the app, as a scenario opens it.
    enum Screen: Identifiable, Equatable {
        case order(id: Int, showsReceipt: Bool)
        case paywall(plan: String, offersTrial: Bool)
        case onboarding(step: Int)

        var id: String {
            title
        }

        /// The screen's name, as its sheet and the Scenarios section show it.
        var title: String {
            switch self {
            case let .order(id, _): "Order #\(id)"
            case let .paywall(plan, _): "Paywall (\(plan))"
            case let .onboarding(step): "Onboarding, step \(step) of \(ProductionScenarios.onboardingSteps)"
            }
        }

        /// What the screen shows under its title.
        var detail: String {
            switch self {
            case let .order(_, showsReceipt): showsReceipt ? "Receipt shown" : "Receipt hidden"
            case let .paywall(_, offersTrial): offersTrial ? "Free trial offered" : "No trial"
            case let .onboarding(step): step == ProductionScenarios.onboardingSteps ? "Last step" : "Continue to step \(step + 1)"
            }
        }
    }

    /// The steps of the example's onboarding.
    nonisolated static let onboardingSteps = 5
    /// The URL that brings the app forward: its own scheme, declared in Info.plist's
    /// `CFBundleURLTypes`, which the iOS sidecar opens. The app needn't
    /// do anything with it.
    static let launchURL = URL(string: "debugdrawer-receiver-example://scenarios")

    /// The screen a scenario opened, shown as a sheet until dismissed.
    @Published var screen: Screen?

    /// The scenarios a sidecar may launch, each bounded to what an employee needs.
    var scenarios: [DebugDrawerScenario] {
        [
            DebugDrawerScenario("open-order", title: "Open Order", summary: "An order's detail screen", parameters: [
                .integer("orderID", title: "Order", default: 123, in: 1 ... 999_999),
                .boolean("showReceipt", title: "Show Receipt")
            ]) { [weak self] arguments in
                self?.screen = .order(id: arguments.integer("orderID") ?? 123, showsReceipt: arguments.boolean("showReceipt") ?? false)
            },
            DebugDrawerScenario("show-paywall", title: "Show Paywall", summary: "The paywall for a plan", parameters: [
                .choice("plan", title: "Plan", options: ["monthly", "annual"]),
                .boolean("offerTrial", title: "Offer Trial", default: true)
            ]) { [weak self] arguments in
                self?.screen = .paywall(plan: arguments.string("plan") ?? "monthly", offersTrial: arguments.boolean("offerTrial") ?? true)
            },
            DebugDrawerScenario("onboarding-step", title: "Onboarding Step", summary: "Onboarding, from a step", parameters: [
                .integer("step", title: "Step", default: 1, in: 1 ... Self.onboardingSteps)
            ]) { [weak self] arguments in
                self?.screen = .onboarding(step: arguments.integer("step") ?? 1)
            }
        ]
    }
}
