#if DEBUG
    import SwiftUI

    /// What the drawer shows under its header after Create Report: progress, the finished zip
    /// with a share button, or why it failed, with a button that dismisses it.
    struct DrawerReportResult: View {
        /// Where the report is.
        enum State: Equatable {
            /// Being written.
            case creating
            /// Written to this zip.
            case ready(URL)
            /// Not written, for this reason.
            case failed(String)
        }

        let state: State
        let dismiss: () -> Void

        var body: some View {
            // The detail gets a line of its own, the panel's full width: a report's file name is
            // too long to share a row with the buttons.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    statusRow
                    Spacer()
                    // tvOS has no share sheet; the detail line names the zip's full path instead.
                    #if !os(tvOS)
                        if case let .ready(url) = state {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .accessibilityHidden(true)
                                    .frame(minWidth: DrawerCloseButton.minimumTapSize, minHeight: DrawerCloseButton.minimumTapSize)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(Color.accentColor)
                            .accessibilityLabel("Share the report")
                        }
                    #endif
                    if state != .creating {
                        Button(action: dismiss) {
                            Image(systemName: "xmark")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                                .frame(minWidth: DrawerCloseButton.minimumTapSize, minHeight: DrawerCloseButton.minimumTapSize)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Dismiss the report result")
                    }
                }
                // The buttons' 44 pt targets supply the row's height and trailing margin.
                .padding(.trailing, 2)
                .frame(minHeight: DrawerCloseButton.minimumTapSize)

                if let detail {
                    Text(detail)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .debugDrawerTextSelection()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 14)
                        .padding(.bottom, 6)
                }
            }
            .padding(.leading, 14)
        }

        @ViewBuilder private var statusRow: some View {
            switch state {
            case .creating:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Creating report…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            case .ready:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Report ready")
                    .font(.callout)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Couldn't create the report")
                    .font(.callout)
            }
        }

        /// The zip's file name (on tvOS, which can't share it, its full path, to fetch from the
        /// app's container), or why the report failed.
        private var detail: String? {
            switch state {
            case .creating: nil
            #if os(tvOS)
                case let .ready(url): url.path
            #else
                case let .ready(url): url.lastPathComponent
            #endif
            case let .failed(reason): reason
            }
        }
    }
#endif
