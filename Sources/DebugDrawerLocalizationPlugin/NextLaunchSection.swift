#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Foundation's own pseudo-localization, stored for the next launch, which reaches every
    /// string, SwiftUI's included: a toggle per setting, then a row saying whether a relaunch is
    /// pending or the app already runs with them, so an accented app always says why.
    struct NextLaunchSection: View {
        /// The settings stored for the next launch.
        let stored: Set<NextLaunchOption>
        /// The settings the app launched with.
        let launchedWith: Set<NextLaunchOption>
        /// Stores a setting, or removes it.
        let onChange: (NextLaunchOption, Bool) -> Void

        var body: some View {
            DebugDrawerSection("Whole App on Next Launch") {
                ForEach(NextLaunchOption.allCases, id: \.self) { option in
                    DebugDrawerRow(option.title, isOn: Binding(get: { stored.contains(option) }, set: { onChange(option, $0) }))
                        .accessibilityHint("Stored in the app's defaults; applies to every string from the next launch")
                }
                status
            } footer: {
                Text("Stored in the app's defaults, so it changes every string from the next launch, the drawer's included.")
            }
        }

        @ViewBuilder private var status: some View {
            if stored != launchedWith {
                DebugDrawerIssueRow(
                    "Relaunch to apply",
                    severity: .warning
                ) {
                    Text(verbatim: stored.isEmpty ? "Off from the next launch." : "Next launch: \(stored.summary).")
                }
            } else if !stored.isEmpty {
                DebugDrawerIssueRow("On in this launch", severity: .warning) {
                    // Verbatim: as a key, the interpolation is a format Foundation's own accenting garbles.
                    Text(verbatim: "\(stored.summary). Turn it off and relaunch to undo.")
                }
            }
        }
    }
#endif
