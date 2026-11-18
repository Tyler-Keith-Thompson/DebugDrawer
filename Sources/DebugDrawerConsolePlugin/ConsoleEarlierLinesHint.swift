#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Under the log, under Previous, while the page leaves out older lines the filter passes: how
    /// many, with Show Earlier, so the list never starts partway through the session without a
    /// word. Nothing shows while the page lists them all.
    struct ConsoleEarlierLinesHint: View {
        /// How many older lines the page leaves out.
        let count: Int
        /// Lists more of them.
        let showEarlier: () -> Void

        var body: some View {
            if count > 0 {
                DebugDrawerRow(title, systemImage: "arrow.up.to.line") {
                    Button("Show Earlier", action: showEarlier)
                        .debugDrawerButtonStyle(.secondary)
                        .accessibilityLabel("Show Earlier")
                        .accessibilityHint("Lists up to \(ConsoleSessionPage.lineCount.formatted()) older lines above these")
                }
            }
        }

        /// "1 earlier line not listed", "95,433 earlier lines not listed".
        var title: String {
            count == 1 ? "1 earlier line not listed" : "\(count.formatted()) earlier lines not listed"
        }
    }
#endif
