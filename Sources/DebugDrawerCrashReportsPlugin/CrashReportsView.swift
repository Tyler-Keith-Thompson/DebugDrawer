#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The reports, newest first, one of them open to its stack trace, then buttons that mark
    /// every report seen and delete them all.
    struct CrashReportsView: View {
        let reports: [CrashReport]
        /// The report open to its stack trace, if any.
        @Binding var expanded: CrashReport.ID?
        /// Called when a report is opened: it is then seen.
        let onOpen: (CrashReport.ID) -> Void
        let onDelete: (CrashReport.ID) -> Void
        let onMarkAllSeen: () -> Void
        let onDeleteAll: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                if reports.isEmpty {
                    Text("No crash reports. After a crash, its report appears here on the next launch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(reports) { report in
                        CrashReportRow(
                            report: report,
                            isExpanded: expanded == report.id,
                            onToggle: { toggle(report.id) },
                            onDelete: { onDelete(report.id) }
                        )
                        Divider()
                    }
                    buttons
                }
            }
        }

        private func toggle(_ id: CrashReport.ID) {
            if expanded == id {
                expanded = nil
            } else {
                expanded = id
                onOpen(id)
            }
        }

        private var buttons: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout())
            return layout {
                Button("Mark All Seen", action: onMarkAllSeen)
                    .disabled(reports.allSatisfy(\.isSeen))
                    .accessibilityHint("Clears the badge without opening each report")
                Button("Delete All", role: .destructive, action: onDeleteAll)
                    .accessibilityHint("Deletes every crash report")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
#endif
