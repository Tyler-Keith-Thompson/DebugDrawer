#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The reports, newest first, one of them open to its stack trace, then buttons that mark
    /// every report seen and delete them all.
    struct CrashReportsView: View {
        let reports: [CrashReport]
        /// The report open to its stack trace, if any.
        @Binding var expanded: CrashReport.ID?
        /// The app's executable's file name, which marks the app's own frames.
        var ownImage: String?
        /// Names the frames' Swift symbols as Xcode does.
        var demangler: any SymbolDemangler = _SymbolDemangler()
        /// Called when a report is opened: it is then seen.
        let onOpen: (CrashReport.ID) -> Void
        let onDelete: (CrashReport.ID) -> Void
        let onMarkAllSeen: () -> Void
        let onDeleteAll: () -> Void

        var body: some View {
            if reports.isEmpty {
                DebugDrawerSection {
                    EmptyView()
                } footer: {
                    Text("No crash reports. After a crash, its report appears here on the next launch.")
                }
            } else {
                DebugDrawerSection {
                    ForEach(reports) { report in
                        CrashReportRow(
                            report: report,
                            isExpanded: expanded == report.id,
                            ownImage: ownImage,
                            demangler: demangler,
                            onToggle: { toggle(report.id) },
                            onDelete: { onDelete(report.id) }
                        )
                    }
                }
                DebugDrawerActionRow {
                    Button("Mark All Seen", action: onMarkAllSeen)
                        .disabled(reports.allSatisfy(\.isSeen))
                        .accessibilityHint("Clears the badge without opening each report")
                } trailing: {
                    Button("Delete All", role: .destructive, action: onDeleteAll)
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityHint("Deletes every crash report")
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
    }
#endif
