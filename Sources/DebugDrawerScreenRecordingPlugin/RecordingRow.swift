#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A saved recording: when it started, its length and size, and Share, In Bug Report and
    /// Delete.
    struct RecordingRow: View {
        let recording: Recording
        let isIncludedInReport: Bool
        let delete: () -> Void
        let setIncludedInReport: (Bool) -> Void
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone

        var body: some View {
            let title = recording.title(locale: locale, timeZone: timeZone)
            DebugDrawerRow(title, systemImage: "film") {
                Text(recording.summary)
                    .debugDrawerFont(.value)
                DebugDrawerActionRow {
                    share(title: title)
                    Button {
                        setIncludedInReport(!isIncludedInReport)
                    } label: {
                        Label(
                            isIncludedInReport ? "In Bug Report" : "Add to Bug Report",
                            systemImage: isIncludedInReport ? "checkmark.circle.fill" : "plus.circle"
                        )
                    }
                    .accessibilityLabel("In bug report")
                    .accessibilityValue(isIncludedInReport ? "Included" : "Not included")
                    .accessibilityHint(isIncludedInReport ? "Leaves the recording out of the bug report" : "Adds the recording to the bug report")
                    // In the wrapping group rather than the row's trailing slot: beside Delete,
                    // Add to Bug Report is wider than an iPad drawer's column and pushes the row
                    // past the panel's edge.
                    Button("Delete", role: .destructive, action: delete)
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel("Delete the recording from \(title)")
                }
            } accessory: {
                EmptyView()
            }
        }

        /// Share, which hands the movie to the share sheet.
        private func share(title: String) -> some View {
            ShareLink(item: recording.url, preview: SharePreview(recording.url.lastPathComponent)) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .accessibilityLabel("Share the recording from \(title)")
        }
    }

    extension Recording {
        /// When it started, as the list names it: the day and the time to the second, in `locale`
        /// and `timeZone` ("Nov 16 at 10:46:40 AM").
        func title(locale: Locale, timeZone: TimeZone) -> String {
            started.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).month(.abbreviated).day().hour().minute().second())
        }
    }
#endif
