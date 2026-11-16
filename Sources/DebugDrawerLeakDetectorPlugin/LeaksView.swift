#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The leak suspects, the most recently flagged first, each with a button that ignores its
    /// class, then how many are ignored with a button that shows them again.
    struct LeaksView: View {
        let suspects: [LeakSuspect]
        /// How many suspects are hidden because their class is ignored.
        let ignoredCount: Int
        let onIgnore: (LeakSuspect) -> Void
        let onStopIgnoring: () -> Void

        var body: some View {
            DebugDrawerSection {
                ForEach(suspects) { suspect in
                    LeakRow(suspect: suspect) { onIgnore(suspect) }
                }
            } footer: {
                if suspects.isEmpty {
                    Text(Self.emptyText)
                }
            }
            if ignoredCount > 0 {
                DebugDrawerActionRow {
                    Text(ignoredCount == 1 ? "1 suspect ignored" : "\(ignoredCount) suspects ignored")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                    Button("Stop Ignoring", action: onStopIgnoring)
                        .accessibilityHint("Shows the ignored classes' suspects again")
                }
            }
        }

        /// What the plugin says with no suspects.
        static let emptyText = """
        No leak suspects. A view controller still alive a run-loop turn after its screen was \
        dismissed appears here, and so does a class with more instances alive than \
        trackLifetime(of:maxCount:) allows.
        """
    }
#endif
