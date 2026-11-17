#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Under the log, while the mutes match lines the other filters pass: how many they hide, with
    /// Show, or while they show, how many are muted, with Hide; and Unmute, a menu of the mutes.
    /// So muted lines are never out of sight without a word. Nothing shows while they match none.
    struct ConsoleMutedHint: View {
        /// How many lines the mutes hide, or would hide.
        let count: Int
        /// The mutes, in the order they were added.
        let mutes: [ConsoleMute]
        /// Whether the muted lines show.
        let isShowing: Bool
        /// Shows the muted lines, or hides them again.
        let toggle: () -> Void
        /// Removes one mute.
        let unmute: (ConsoleMute) -> Void
        /// Removes every mute.
        let unmuteAll: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            if count > 0 {
                // Two buttons beside the title at their ideal width; at accessibility sizes they
                // move to an action row under it, which wraps them, since side by side they would
                // be wider than the drawer.
                if dynamicTypeSize.isAccessibilitySize {
                    DebugDrawerRow(title, systemImage: symbol) {
                        DebugDrawerActionRow { buttons }
                    } accessory: {
                        EmptyView()
                    }
                } else {
                    DebugDrawerRow(title, systemImage: symbol) {
                        HStack(spacing: 6) { buttons }
                            .fixedSize()
                    }
                }
            }
        }

        @ViewBuilder private var buttons: some View {
            Button(isShowing ? "Hide" : "Show", action: toggle)
                .debugDrawerButtonStyle(.secondary)
                .accessibilityLabel(isShowing ? "Hide muted lines" : "Show muted lines")
            Menu("Unmute") {
                ForEach(mutes, id: \.self) { mute in
                    Button(mute.title) { unmute(mute) }
                        .accessibilityLabel("Unmute \(mute.title)")
                }
                Divider()
                Button("Unmute All", action: unmuteAll)
                    .accessibilityLabel("Unmute All")
            }
            .menuStyle(.button)
            .debugDrawerButtonStyle(.secondary)
            .fixedSize()
            .accessibilityLabel("Unmute")
        }

        private var symbol: String {
            isShowing ? "eye" : "eye.slash"
        }

        private var title: String {
            isShowing ? "\(count.formatted()) muted, shown" : "\(count.formatted()) muted"
        }
    }
#endif
