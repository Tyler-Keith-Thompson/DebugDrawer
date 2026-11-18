#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The views tracked with `.trackRenders(_:)` and how many times each body was evaluated, in
    /// the order given, as issue rows: OK up to 3 evaluations, a warning up to 10, an error above.
    /// A summary row above them resets the counts; with none, a row says how to track a view.
    struct RenderCountList: View {
        /// In the order shown, busiest first.
        let entries: [RenderTracker.Entry]
        /// Forgets every count.
        let reset: () -> Void

        var body: some View {
            if entries.isEmpty {
                DebugDrawerRow("No tracked views") {
                    Text("Add .trackRenders(\"Name\") to a view's body to count its renders.")
                } accessory: {
                    EmptyView()
                }
            } else {
                DebugDrawerRow(Self.summary(of: entries)) {
                    Button("Reset", action: reset)
                        .debugDrawerButtonStyle(.borderless)
                        .accessibilityLabel("Reset render counts")
                }
                ForEach(entries) { entry in
                    DebugDrawerIssueRow(
                        entry.id,
                        status: entry.count == 1 ? "1 render" : "\(entry.count) renders",
                        severity: Self.severity(forCount: entry.count)
                    )
                }
            }
        }
    }

    extension RenderCountList {
        fileprivate static func summary(of entries: [RenderTracker.Entry]) -> String {
            let views = entries.count == 1 ? "1 view" : "\(entries.count) views"
            let total = entries.reduce(0) { $0 + $1.count }
            let renders = total == 1 ? "1 render" : "\(total) renders"
            return "\(views), \(renders)"
        }

        fileprivate static func severity(forCount count: Int) -> DebugDrawerIssueGlyph.Severity {
            if count <= 3 { return .ok }
            if count <= 10 { return .warning }
            return .error
        }
    }
#endif
