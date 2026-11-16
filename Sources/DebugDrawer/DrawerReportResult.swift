#if DEBUG
    import SwiftUI

    /// What the drawer shows under its header after Create Report: progress, the finished zip
    /// with a share button (and Send Report when the app set an uploader), the upload's progress
    /// and outcome, or why the report failed, with a button that dismisses it.
    struct DrawerReportResult: View {
        /// Where the report is.
        enum State: Equatable {
            /// Being written.
            case creating
            /// Written to this zip.
            case ready(URL)
            /// This zip is being sent; `progress` is the fraction sent, from 0 to 1.
            case uploading(URL, progress: Double)
            /// This zip was sent.
            case sent(URL)
            /// Not written, for this reason.
            case failed(String)
            /// This zip, still on disk, wasn't sent, for this reason.
            case uploadFailed(URL, reason: String)

            /// The report is being written or sent: it can't be dismissed, and another can't be started.
            var isInProgress: Bool {
                switch self {
                case .creating, .uploading: true
                case .ready, .sent, .failed, .uploadFailed: false
                }
            }
        }

        let state: State
        /// Sends the zip; nil when the app set no uploader, which hides Send Report and Retry.
        var send: ((URL) -> Void)?
        let dismiss: () -> Void

        var body: some View {
            // The detail gets a line of its own, the panel's full width: a report's file name is
            // too long to share a row with the buttons.
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    statusRow
                    Spacer()
                    if let send, let archive = sendableArchive {
                        sendButton(retrying: state != .ready(archive)) { send(archive) }
                    }
                    // tvOS has no share sheet; the detail line names the zip's full path instead.
                    #if !os(tvOS)
                        if let archive = shareableArchive {
                            ShareLink(item: archive) {
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
                    if !state.isInProgress {
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

                if case let .uploading(_, progress) = state {
                    ProgressView(value: progress)
                        .accessibilityLabel("Sending the report")
                        .padding(.trailing, 14)
                        .padding(.bottom, 6)
                }

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

        /// Send Report beside a ready zip, Retry beside one whose upload failed.
        private func sendButton(retrying: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Image(systemName: retrying ? "arrow.clockwise" : "paperplane")
                    .accessibilityHidden(true)
                    .frame(minWidth: DrawerCloseButton.minimumTapSize, minHeight: DrawerCloseButton.minimumTapSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            .accessibilityLabel(retrying ? "Retry sending the report" : "Send the report")
            .help(retrying ? "Retry sending the report" : "Send the report")
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
            case let .uploading(_, progress):
                Image(systemName: "paperplane")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Sending report…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(progress, format: .percent.precision(.fractionLength(0)))
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(.secondary)
            case .sent:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Report sent")
                    .font(.callout)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Couldn't create the report")
                    .font(.callout)
            case .uploadFailed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Couldn't send the report")
                    .font(.callout)
            }
        }

        /// The zip Send Report (when ready) or Retry (when the upload failed) sends.
        private var sendableArchive: URL? {
            switch state {
            case let .ready(archive), let .uploadFailed(archive, _): archive
            case .creating, .uploading, .sent, .failed: nil
            }
        }

        /// The zip the share button offers: a finished report that isn't being sent.
        private var shareableArchive: URL? {
            switch state {
            case let .ready(archive), let .uploadFailed(archive, _), let .sent(archive): archive
            case .creating, .uploading, .failed: nil
            }
        }

        /// The zip's file name (on tvOS, which can't share it, its full path, to fetch from the
        /// app's container), or why the report or its upload failed.
        private var detail: String? {
            switch state {
            case .creating: nil
            #if os(tvOS)
                case let .ready(url), let .uploading(url, _), let .sent(url): url.path
            #else
                case let .ready(url), let .uploading(url, _), let .sent(url): url.lastPathComponent
            #endif
            case let .failed(reason), let .uploadFailed(_, reason): reason
            }
        }
    }
#endif
