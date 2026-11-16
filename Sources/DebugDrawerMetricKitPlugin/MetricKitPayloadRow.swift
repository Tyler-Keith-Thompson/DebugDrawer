#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One payload as an issue row: the unread dot until it is opened, a glyph for what it holds
    /// (an error for crashes, a warning for other diagnostics), its kind, what it holds and the
    /// period it covers, and, open, its formatted JSON with buttons that copy, export and delete it.
    /// The summary takes the row's width: the row opens on a tap, so it needs no chevron, and
    /// Delete sits with the other actions once open, as a crash report's does.
    struct MetricKitPayloadRow: View {
        let payload: MetricKitPayload
        let isExpanded: Bool
        let onToggle: () -> Void
        let onDelete: () -> Void
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone
        /// The tallest the JSON gets before it scrolls: a day's metrics run to hundreds of lines.
        @ScaledMetric(relativeTo: .body) private var jsonHeight: CGFloat = 280

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    // The dot keeps its column on a seen row too, so the glyphs line up.
                    DebugDrawerUnreadDot()
                        .opacity(payload.isSeen ? 0 : 1)
                        .accessibilityHidden(payload.isSeen)
                    Button(action: onToggle) {
                        summary
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .debugDrawerButtonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(isExpanded ? "Hides the JSON" : "Shows the JSON")
                }
                if isExpanded {
                    json
                }
            }
        }

        private var summary: some View {
            DebugDrawerIssueRow(payload.kind.title, severity: payload.summary.severity) {
                Text(payload.summary.text)
                Text(period)
            }
        }

        /// The period the payload covers, in the view's locale and time zone.
        private var period: String {
            payload.period.formatted(Date.IntervalFormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
        }

        private var json: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerCodeBlock {
                    ScrollView(.vertical) {
                        // Long lines wrap, so the whole of each shows in the drawer's width.
                        Text(payload.formattedJSON)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: jsonHeight)
                    .fixedSize(horizontal: false, vertical: true)
                }
                DebugDrawerActionRow {
                    DebugDrawerCopyButton("Copy JSON") { payload.formattedJSON }
                    ShareLink(
                        item: MetricKitPayloadFile(payload: payload),
                        preview: SharePreview(payload.exportFileName)
                    ) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export the payload as a JSON file")
                } trailing: {
                    Button("Delete", role: .destructive, action: onDelete)
                        .debugDrawerButtonStyle(.destructive)
                        .accessibilityLabel("Delete \(payload.kind.title.lowercased()) payload of \(period)")
                }
            }
        }
    }

    extension MetricKitPayloadSummary {
        /// The glyph for what a payload holds: an error for crashes, a warning for other
        /// diagnostics, ok for metrics or a diagnostics payload with none, and unknown for one
        /// that can't be read.
        fileprivate var severity: DebugDrawerIssueGlyph.Severity {
            switch self {
            case .metrics:
                .ok
            case let .diagnostics(counts) where counts.crashes > 0:
                .error
            case let .diagnostics(counts) where counts.hangs + counts.cpuExceptions + counts.diskWriteExceptions + counts.slowLaunches > 0:
                .warning
            case .diagnostics:
                .ok
            case .unreadable:
                .neutral
            }
        }
    }
#endif
