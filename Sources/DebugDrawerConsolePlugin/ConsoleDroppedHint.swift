#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Under the log, once the console's bounds dropped older lines: how many, so the list never
    /// starts after the app's first line without a word. Nothing shows while none were dropped.
    struct ConsoleDroppedHint: View {
        /// How many older lines the bounds dropped.
        let count: Int

        var body: some View {
            if count > 0 {
                DebugDrawerRow(title, systemImage: "tray.full") { EmptyView() }
            }
        }

        /// "1 older line dropped", "2,400 older lines dropped".
        var title: String {
            count == 1 ? "1 older line dropped" : "\(count.formatted()) older lines dropped"
        }
    }
#endif
