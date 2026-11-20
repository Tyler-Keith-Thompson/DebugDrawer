#if DEBUG
    import DebugDrawer
    import DebugDrawerAppStateReset
    import SwiftUI

    /// One thing a category will delete: its name, cut in the middle to fit, and its size, count
    /// or domain.
    struct PlanLineRow: View {
        let line: PlanLine

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(line.text)
                    .debugDrawerFont(.code)
                    .debugDrawerForegroundStyle(.primary)
                    // A long path is cut in the middle, where its least telling part is.
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let detail = line.detail {
                    Text(detail)
                        .debugDrawerFont(.value)
                        .debugDrawerForegroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
#endif
