#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Under the log, while a time range limits it: the range, with Show All. So a range never
    /// hides lines without a word. Nothing shows while the range is All.
    struct ConsoleTimeRangeHint: View {
        let timeRange: ConsoleTimeRange
        /// Lists every line again.
        let showAll: () -> Void

        var body: some View {
            if timeRange != .all {
                DebugDrawerRow(timeRange.title, systemImage: "clock") {
                    Button("Show All", action: showAll)
                        .debugDrawerButtonStyle(.secondary)
                        .accessibilityLabel("Show All")
                        .accessibilityHint("Shows lines from any time")
                }
            }
        }
    }
#endif
