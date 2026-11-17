#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// "3G active" (or, in the header, "1 active") after a tortoise in the accent color, while
    /// conditioning profiles are on, so a slow or failing app is never mistaken for a slow or
    /// failing server. Nothing while none is.
    struct NetworkConditionsIndicator: View {
        /// What VoiceOver says: `[NetworkConditionProfile].activeSummary`.
        let summary: String?
        /// What it shows, when shorter than `summary`: the header's
        /// `[NetworkConditionProfile].activeCountLabel`.
        var label: String?
        /// Whether the text shows beside the tortoise; the header leaves it out when its row has
        /// no room. VoiceOver reads `summary` either way.
        var showsLabel = true

        var body: some View {
            if let summary {
                HStack(spacing: 4) {
                    Image(systemName: "tortoise.fill")
                        .accessibilityHidden(true)
                    if showsLabel {
                        Text(label ?? summary)
                    }
                }
                // A few words that never truncate: the warning matters more than the counts
                // beside it. The drawer moves a header accessory too wide for the row under it.
                .fixedSize()
                .debugDrawerForegroundStyle(.accent)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Network conditions: \(summary)")
            }
        }
    }

    /// The Network plugin's HUD readout: the conditions that are on, so they show with the drawer
    /// closed, or "Network unconditioned" while none is.
    public struct NetworkConditionsHUD: View {
        @ObservedObject var conditions: NetworkConditionsModel

        public var body: some View {
            NetworkConditionsHUDReadout(summary: conditions.profiles.activeSummary)
        }
    }

    /// The HUD's readout for `summary`: the indicator, or "Network unconditioned" in the secondary
    /// color while no profile is on.
    struct NetworkConditionsHUDReadout: View {
        let summary: String?

        var body: some View {
            Group {
                if summary == nil {
                    Label("Network unconditioned", systemImage: "network")
                        .debugDrawerForegroundStyle(.secondary)
                } else {
                    NetworkConditionsIndicator(summary: summary)
                }
            }
            .debugDrawerFont(.value)
        }
    }
#endif
