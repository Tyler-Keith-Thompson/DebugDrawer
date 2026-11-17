#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The confirmation: exactly what the reset will delete, category by category and line by
    /// line, with Cancel, Reset and Reset and Relaunch (or Quit).
    struct ResetConfirmationView: View {
        let plan: ResetPlan
        /// The categories selected, in the drawer's order.
        let categories: [ResetCategory]
        let restartStyle: RestartStyle
        let cancel: () -> Void
        let reset: () -> Void
        let resetAndRestart: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Reset app state?")
                    .debugDrawerFont(.title)
                    .accessibilityAddTraits(.isHeader)
                Text("These are deleted, and can't be brought back:")
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.secondary)
                    .padding(.top, 4)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(categories) { category in
                            ConfirmationCategorySection(category: category, summary: plan.summary(of: category), lines: plan.lines(of: category))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if restartStyle == .quit {
                    Text(Self.quitNote)
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }
                DebugDrawerActionRow {
                    Button("Cancel", action: cancel)
                        .accessibilityLabel("Cancel the reset")
                } trailing: {
                    Button("Reset", role: .destructive, action: reset)
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel("Reset, and keep the app running")
                    Button(restartStyle == .relaunch ? "Reset and Relaunch" : "Reset and Quit", role: .destructive, action: resetAndRestart)
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel(restartStyle == .relaunch ? "Reset and Relaunch the app" : "Reset and Quit the app")
                }
            }
            .padding()
        }

        /// Where to open the app again once it has quit.
        static var quitNote: String {
            #if targetEnvironment(macCatalyst)
                "Reset and Quit quits the app; an app can't relaunch itself. Open it again from the Dock or the Finder."
            #elseif os(visionOS)
                "Reset and Quit quits the app; an app can't relaunch itself. Open it again from the Home View."
            #else
                "Reset and Quit quits the app; an app can't relaunch itself. Open it again from the Home Screen."
            #endif
        }
    }

    /// One category in the confirmation: its name and summary, then every line it will delete.
    struct ConfirmationCategorySection: View {
        let category: ResetCategory
        let summary: String
        let lines: [PlanLine]

        var body: some View {
            DebugDrawerSection("\(category.title): \(summary)") {
                if lines.isEmpty {
                    Text("Nothing to delete.")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        // By position: two keychain items can share a name.
                        ForEach(Array(lines.enumerated()), id: \.offset) { PlanLineRow(line: $0.element) }
                    }
                }
            }
        }
    }
#endif
