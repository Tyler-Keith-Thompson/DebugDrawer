#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The status filter, then the log's actions: export the requests shown as a HAR file, import
    /// one, and, at the trailing edge, clear the requests shown. The request count is the header's
    /// accessory, so the toolbar doesn't repeat it.
    struct NetworkToolbar: View {
        @Binding var filterStatus: NetworkStore.StatusFilter
        let clear: () -> Void
        /// The requests the log shows, to export; `nil` offers no export.
        var export: NetworkArchiveFile?
        /// Whether a filter hides some of the requests, so the export says it holds only those shown.
        var isFiltered = false
        /// Opens the file importer for a HAR file; `nil` offers no import.
        var importArchive: (() -> Void)?
        /// What the trailing button clears.
        var source = NetworkLogSource.captured

        var body: some View {
            // The filter has a line of its own: its five segments at their ideal width are wider
            // than the drawer on iPad, and squeezed beside Clear they would truncate.
            VStack(alignment: .leading, spacing: 0) {
                Picker("Status", selection: $filterStatus) {
                    ForEach(NetworkStore.StatusFilter.allCases, id: \.self) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityLabel("Status")
                .accessibilityElement(children: .contain)
                .padding(.top, 8)
                DebugDrawerActionRow {
                    exportButton
                    if let importArchive {
                        Button("Import HAR…", action: importArchive)
                            .accessibilityLabel("Import HAR…")
                            .accessibilityHint("Shows the requests in a HAR file, read-only, in place of the captured ones")
                    }
                } trailing: {
                    Button("Clear", role: .destructive, action: clear)
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel(source == .imported ? "Clear imported requests" : "Clear requests")
                }
            }
        }

        /// Export All, or Export Shown while a filter hides some requests: the requests the log
        /// lists, as a HAR file, through the share sheet. Nothing to export disables it.
        @ViewBuilder private var exportButton: some View {
            if let export {
                let title = isFiltered ? "Export Shown" : "Export All"
                let count = export.entries.count
                ShareLink(item: export, preview: SharePreview(export.fileName)) {
                    Text(title)
                }
                .disabled(export.entries.isEmpty)
                .accessibilityLabel(title)
                .accessibilityHint("Shares the \(count == 1 ? "request" : "\(count) requests") the list shows as a HAR file, sensitive values masked")
            }
        }
    }
#endif
