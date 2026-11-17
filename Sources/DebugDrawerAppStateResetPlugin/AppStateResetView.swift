#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the last reset's results, a checkbox per category with what it will
    /// delete, whether DebugDrawer's own settings go too, Refresh, and Reset…, which opens the
    /// confirmation. It keeps whether the confirmation is open.
    struct AppStateResetView: View {
        let state: ResetState
        @Binding var selection: Set<ResetCategory>
        @Binding var includesDebugDrawer: Bool
        let restartStyle: RestartStyle
        let refresh: () -> Void
        /// Resets the selected categories; `true` relaunches or quits afterwards.
        let reset: (Bool) -> Void
        @State var isConfirming = false
        let inspection = Inspection<Self>()

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if case let .finished(_, result, restart) = state {
                    ResetResultSection(result: result, restart: restart)
                }
                switch state {
                case .loading:
                    progressRow("Reading the app's state…", label: "Reading")
                case .resetting:
                    progressRow("Resetting…", label: "Resetting")
                case .ready, .finished:
                    EmptyView()
                }
                if let plan = state.plan {
                    DebugDrawerSection("Clear") {
                        ForEach(plan.categories) { category in
                            // The app's cleanup is one line, its title, which the summary shows.
                            ResetCategoryRow(
                                category: category, summary: plan.summary(of: category),
                                lines: category == .appCleanup ? [] : plan.lines(of: category),
                                problem: plan.problem(of: category), isSelected: isSelected(category)
                            )
                        }
                    } footer: {
                        Text("Files is Documents, Application Support and tmp, and each app group's container; Caches is cleared on its own.")
                    }
                    DebugDrawerSection {
                        DebugDrawerRow("Include DebugDrawer's own settings", systemImage: "gearshape", isOn: $includesDebugDrawer)
                    } footer: {
                        Text("""
                        Off keeps the drawer's layout, HUD pins and plugin settings (keys starting com.debugdrawer.) \
                        and its files, such as recordings in Caches/DebugDrawer.
                        """)
                    }
                }
                DebugDrawerActionRow {
                    Button("Refresh", action: refresh)
                        .disabled(isBusy)
                        .accessibilityLabel("Refresh what each category holds")
                } trailing: {
                    Button("Reset…", role: .destructive) { isConfirming = true }
                        .debugDrawerButtonStyle(.destructive)
                        .disabled(isBusy || state.plan == nil || selected.isEmpty)
                        .accessibilityLabel("Reset…")
                        .accessibilityHint("Lists what the selected categories will delete, to confirm")
                }
            }
            .sheet(isPresented: $isConfirming) {
                if let plan = state.plan {
                    ResetConfirmationView(
                        plan: plan, categories: selected, restartStyle: restartStyle,
                        cancel: { isConfirming = false },
                        reset: { confirm(restarting: false) },
                        resetAndRestart: { confirm(restarting: true) }
                    )
                    #if os(macOS)
                    .frame(minWidth: 380, idealWidth: 440, minHeight: 320, idealHeight: 520)
                    #endif
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        /// The selected categories this app has, in the drawer's order.
        var selected: [ResetCategory] {
            (state.plan?.categories ?? []).filter(selection.contains)
        }

        private var isBusy: Bool {
            switch state {
            case .loading, .resetting: true
            case .ready, .finished: false
            }
        }

        private func confirm(restarting: Bool) {
            isConfirming = false
            reset(restarting)
        }

        private func isSelected(_ category: ResetCategory) -> Binding<Bool> {
            Binding {
                selection.contains(category)
            } set: { isOn in
                if isOn { selection.insert(category) } else { selection.remove(category) }
            }
        }

        private func progressRow(_ title: String, label: String) -> some View {
            DebugDrawerRow(title, systemImage: "arrow.counterclockwise") {
                EmptyView()
            } accessory: {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(label)
            }
        }
    }
#endif
