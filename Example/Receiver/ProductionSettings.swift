import DebugDrawerReceiver
import Foundation
import SwiftUI

/// The example's own settings, kept in the standard defaults, which a sidecar may read and edit
/// through the allowlisted UserDefaults capability: the plan, whether tips show and how many items
/// a page lists. Nothing else of the app's defaults is listed: the keys Seed Data writes, the
/// capabilities' own records and the system's stay out of the sidecar's reach.
enum ProductionSettings {
    static let plan = "example.plan"
    static let showsTips = "example.showsTips"
    static let itemsPerPage = "example.itemsPerPage"

    /// The allowlist a sidecar edits within, made as the app starts, so edits a killed session
    /// left are put back before the screen reads them. The registered defaults are what a removed
    /// key reads, and what a key the app never wrote is put back to.
    @MainActor
    static func model() -> DebugDrawerUserDefaults {
        UserDefaults.standard.register(defaults: [plan: "free", itemsPerPage: 20])
        return DebugDrawerUserDefaults(
            .choice(plan, title: "Plan", options: ["free", "pro", "team"]),
            .bool(showsTips, title: "Shows Tips"),
            .integer(itemsPerPage, title: "Items per Page", in: 10 ... 100)
        )
    }
}

/// The settings as the app reads them, so a sidecar's edit shows at once.
struct ProductionSettingsSection: View {
    @AppStorage(ProductionSettings.plan) private var plan = "free"
    @AppStorage(ProductionSettings.showsTips) private var showsTips = false
    @AppStorage(ProductionSettings.itemsPerPage) private var itemsPerPage = 20

    var body: some View {
        Section {
            LabeledContent("Plan", value: plan.capitalized)
                .accessibilityIdentifier("SettingsPlan")
            LabeledContent("Items per Page", value: String(itemsPerPage))
                .accessibilityIdentifier("SettingsItemsPerPage")
            if showsTips {
                Label("Tip: a sidecar can change these settings for its session.", systemImage: "lightbulb")
                    .accessibilityIdentifier("SettingsTip")
            }
        } header: {
            Text("UserDefaults")
        } footer: {
            Text("A sidecar may edit these three keys and no other; its edits are audited and put back as the session ends.")
        }
    }
}
