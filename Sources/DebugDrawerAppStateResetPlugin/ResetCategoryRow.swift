#if DEBUG
    import DebugDrawer
    import DebugDrawerAppStateReset
    import SwiftUI

    /// A category with its checkbox and what it will delete in a few words, and, opened, line by
    /// line. It keeps whether the lines are shown.
    struct ResetCategoryRow: View {
        let category: AppStateReset.Category
        let summary: String
        let lines: [PlanLine]
        /// Why the category can't be read, such as the keychain's error; `nil` when it can.
        let problem: String?
        @Binding var isSelected: Bool
        @State var isExpanded = false
        let inspection = Inspection<Self>()

        var body: some View {
            DebugDrawerRow(category.title, systemImage: category.systemImage) {
                Text(summary)
                    .debugDrawerFont(.value)
                if let problem {
                    Text(problem)
                        .debugDrawerForegroundStyle(.error)
                }
                if !lines.isEmpty {
                    // A button rather than a DisclosureGroup, which tvOS doesn't have and AppKit
                    // draws on the Mac.
                    Button {
                        isExpanded.toggle()
                    } label: {
                        Label(isExpanded ? "Hide details" : "Show details", systemImage: isExpanded ? "chevron.down" : "chevron.right")
                            .debugDrawerFont(.secondary)
                    }
                    .debugDrawerButtonStyle(.borderless)
                    .accessibilityLabel(isExpanded ? "Hide details of \(category.title)" : "Show details of \(category.title)")
                    if isExpanded {
                        VStack(alignment: .leading, spacing: 2) {
                            // By position: two keychain items can share a name.
                            ForEach(Array(lines.enumerated()), id: \.offset) { PlanLineRow(line: $0.element) }
                        }
                    }
                }
            } accessory: {
                Toggle(isOn: $isSelected) { Text(category.title) }
                    .accessibilityLabel("Clear \(category.title)")
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }
    }
#endif
