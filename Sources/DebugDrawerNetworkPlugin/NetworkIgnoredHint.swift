#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Under the log, while the ignore list matches requests the filters pass: how many it hides,
    /// with Show, or while they show, how many are from ignored hosts, with Hide. So ignored
    /// traffic is never out of sight without a word. Nothing shows while it matches none.
    struct NetworkIgnoredHint: View {
        /// How many requests and connections the ignore list hides, or would hide.
        let count: Int
        /// Whether they show.
        let isShowing: Bool
        /// Shows them, or hides them again.
        let toggle: () -> Void

        var body: some View {
            if count > 0 {
                DebugDrawerRow(title, systemImage: isShowing ? "eye" : "eye.slash") {
                    Button(isShowing ? "Hide" : "Show", action: toggle)
                        .debugDrawerButtonStyle(.secondary)
                        .accessibilityLabel(isShowing ? "Hide ignored requests" : "Show ignored requests")
                }
            }
        }

        private var title: String {
            isShowing ? "\(count.formatted()) from ignored hosts shown" : "\(count.formatted()) hidden by ignore list"
        }
    }
#endif
