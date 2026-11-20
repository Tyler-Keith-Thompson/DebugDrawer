#if DEBUG
    import DebugDrawer
    import DebugDrawerAppStateReset
    import SwiftUI

    /// What the last reset did: each category cleared, or what in it couldn't be deleted and why,
    /// and a restart that didn't happen.
    struct ResetResultSection: View {
        let result: ResetResult
        let restart: RestartOutcome

        var body: some View {
            DebugDrawerSection("Last reset") {
                ForEach(result.categories) { category in
                    switch result.outcomes[category] {
                    case let .cleared(count)?:
                        DebugDrawerIssueRow(category.title, status: "Cleared", severity: .ok) {
                            if let cleared = clearedText(count, category) { Text(cleared) }
                        }
                    case let .failed(cleared, failures)?:
                        DebugDrawerIssueRow(category.title, status: "\(failures.count.formatted()) not deleted", severity: .error) {
                            if let cleared = clearedText(cleared, category) { Text(cleared) }
                            ForEach(Array(failures.enumerated()), id: \.offset) { Text($0.element.message) }
                        }
                    case nil:
                        EmptyView()
                    }
                }
                switch restart {
                case .none:
                    EmptyView()
                case .heldForFailures:
                    DebugDrawerIssueRow("Not restarted", severity: .warning) {
                        Text("Something wasn't deleted, so the app kept running for it to be read.")
                    }
                case let .failed(failure):
                    DebugDrawerIssueRow("Not relaunched", severity: .error) {
                        Text(failure.message)
                    }
                }
            }
        }

        /// "12 keys deleted", or `nil` for a category that clears as a whole.
        private func clearedText(_ count: Int, _ category: AppStateReset.Category) -> String? {
            category.noun.map { "\(ResetPlan.count(count, $0, none: "Nothing")) deleted" }
        }
    }
#endif
