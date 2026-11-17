#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The Entitlements section: a row per entitlement, the common ones by name, with where they
    /// were read below; or a None row when the app has none.
    struct AppInfoEntitlementsSection: View {
        let entitlements: Entitlements?

        var body: some View {
            if let entitlements, !entitlements.entries.isEmpty {
                DebugDrawerSection("Entitlements") {
                    ForEach(entitlements.entries, id: \.key) { entitlement in
                        EntitlementRow(entitlement: entitlement)
                    }
                } footer: {
                    Text(entitlements.source.footnote)
                }
            } else {
                DebugDrawerSection("Entitlements") {
                    DebugDrawerKeyValueRow("Entitlements", value: "None")
                }
            }
        }
    }

    /// One entitlement: a switch's Yes or No at the trailing edge, or each item of a list
    /// (an associated domain, an app group) on a line of its own below the name.
    struct EntitlementRow: View {
        let entitlement: Entitlement

        var body: some View {
            switch entitlement.value {
            case let .boolean(isOn):
                DebugDrawerRow(entitlement.label) {
                    Text(isOn ? "Yes" : "No")
                }
            case let .list(items):
                DebugDrawerRow(entitlement.label) {
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        // Wrapped rather than cut in the middle (DebugDrawerCodeText): a domain
                        // or a group is read whole, and at accessibility sizes a cut one hid
                        // most of itself.
                        Text(item)
                            .debugDrawerFont(.code)
                            .textSelection(.enabled)
                    }
                } accessory: {
                    EmptyView()
                }
            }
        }
    }

    extension Entitlements.Source {
        /// The section's note on where the entitlements were read.
        fileprivate var footnote: String {
            switch self {
            case .codeSignature: "From the app's code signature."
            case .executable: "Linked into the executable, as a simulator build has them."
            case .provisioningProfile: "Allowed by the provisioning profile; the app's signature may hold fewer."
            }
        }
    }
#endif
