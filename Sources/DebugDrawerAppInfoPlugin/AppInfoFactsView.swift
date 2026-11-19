#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The facts, in sections, then the provisioning profile and the entitlements, with buttons
    /// to copy them all and to read them again.
    struct AppInfoFactsView: View {
        let facts: AppInfoFacts
        let refresh: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(facts.sections, id: \.title) { section in
                    DebugDrawerSection(section.title) {
                        ForEach(section.facts, id: \.label) { fact in
                            DebugDrawerKeyValueRow(fact.label, value: fact.value)
                        }
                    }
                }
                AppInfoProvisioningSection(profile: facts.signing.profile, isExpired: facts.isProfileExpired)
                AppInfoEntitlementsSection(entitlements: facts.signing.entitlements)

                DebugDrawerActionRow {
                    DebugDrawerCopyButton("Copy Info") { facts.report }
                    Button("Refresh", action: refresh)
                }
            }
        }
    }
#endif
