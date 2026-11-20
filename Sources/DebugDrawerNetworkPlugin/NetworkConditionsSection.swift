#if DEBUG
    import DebugDrawer
    import DebugDrawerNetwork
    import SwiftUI

    /// The Conditions section: the profiles in the order they are tried, each with its switch, then
    /// a note on how they apply, and Add Condition. A problem reading or saving them shows above
    /// the list.
    struct NetworkConditionsSection: View {
        let profiles: [NetworkConditionProfile]
        let issue: NetworkMocksIssue?
        /// The profile whose actions show, if any.
        @Binding var selected: NetworkConditionProfile.ID?
        let setEnabled: (NetworkConditionProfile.ID, Bool) -> Void
        let add: () -> Void
        let edit: (NetworkConditionProfile) -> Void
        let move: (NetworkConditionProfile.ID, Int) -> Void
        let delete: (NetworkConditionProfile.ID) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection("Conditions") {
                    if let issue {
                        DebugDrawerIssueRow(issue == .notSaved ? "Not saved" : "Not loaded", severity: issue == .notSaved ? .warning : .error) {
                            Text(issue.message(about: "conditions"))
                        }
                    }
                    ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                        NetworkConditionRow(
                            profile: profile,
                            isSelected: selected == profile.id,
                            isFirst: index == 0,
                            isLast: index == profiles.count - 1,
                            onSelect: { selected = selected == profile.id ? nil : profile.id },
                            setEnabled: { setEnabled(profile.id, $0) },
                            edit: { edit(profile) },
                            move: { move(profile.id, $0) },
                            delete: {
                                selected = nil
                                delete(profile.id)
                            }
                        )
                    }
                } footer: {
                    Text(profiles.isEmpty
                        ? "No conditions. Add one to slow down or fail the requests to a host."
                        : "The first condition that is on and matches a request's host applies, to mocked and real answers alike. "
                            + "Requests to other hosts are untouched.")
                }
                DebugDrawerActionRow {
                    Button("Add Condition", action: add)
                        .accessibilityLabel("Add Condition")
                }
            }
        }
    }
#endif
