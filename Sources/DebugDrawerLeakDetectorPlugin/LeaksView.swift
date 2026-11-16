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
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if suspects.isEmpty {
                    Text(Self.emptyText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(suspects) { suspect in
                        LeakRow(suspect: suspect) { onIgnore(suspect) }
                        Divider()
                    }
                }
                if ignoredCount > 0 {
                    ignoredFooter
                }
            }
        }

        /// What the plugin says with no suspects.
        static let emptyText = """
        No leak suspects. A view controller still alive a run-loop turn after its screen was \
        dismissed appears here, and so does a class with more instances alive than \
        trackLifetime(of:maxCount:) allows.
        """

        /// How many are ignored and the button that shows them again: side by side, or one above
        /// the other at accessibility text sizes.
        private var ignoredFooter: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            return layout {
                Text(ignoredCount == 1 ? "1 suspect ignored" : "\(ignoredCount) suspects ignored")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Stop Ignoring", action: onStopIgnoring)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityHint("Shows the ignored classes' suspects again")
            }
        }
    }
#endif
