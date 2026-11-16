#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// View types and how many times each rendered, as issue rows: OK up to 3 renders, a warning
    /// up to 10, an error above.
    struct RenderCountList: View {
        /// In the order shown, most renders first.
        let entries: [RenderTracker.Entry]

        var body: some View {
            ForEach(entries) { entry in
                DebugDrawerIssueRow(
                    entry.id,
                    status: entry.count == 1 ? "1 render" : "\(entry.count) renders",
                    severity: Self.severity(forCount: entry.count)
                )
            }
        }

        private static func severity(forCount count: Int) -> DebugDrawerIssueGlyph.Severity {
            if count <= 3 { return .ok }
            if count <= 10 { return .warning }
            return .error
        }
    }
#endif
