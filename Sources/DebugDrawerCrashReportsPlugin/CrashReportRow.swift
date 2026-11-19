#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One report as an issue row: an error glyph, what crashed, why, and when and in which version,
    /// an unread dot until it is opened, and, open, its stack trace as the debug navigator shows one
    /// (the app's own frames badged, the first of them selected), with Copy Report and Delete.
    struct CrashReportRow: View {
        let report: CrashReport
        let isExpanded: Bool
        /// The app's executable's file name, which marks the app's own frames.
        let ownImage: String?
        /// Names the frames' Swift symbols as Xcode does; Copy Report still copies them as recorded.
        let demangler: any SymbolDemangler
        let onToggle: () -> Void
        let onDelete: () -> Void
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onToggle) {
                    DebugDrawerIssueRow(report.title, severity: .error) {
                        if let reason = report.reason {
                            Text(reason)
                                .lineLimit(isExpanded ? nil : 2)
                        }
                        Text(facts)
                    } accessory: {
                        HStack(spacing: 6) {
                            if !report.isSeen {
                                DebugDrawerUnreadDot()
                                    .accessibilityLabel("New report")
                            }
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .debugDrawerFont(.secondary)
                                .debugDrawerForegroundStyle(.tertiary)
                                .accessibilityHidden(true)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .debugDrawerButtonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(isExpanded ? "Hides the stack trace" : "Shows the stack trace")
                if isExpanded {
                    stackTrace
                }
            }
        }

        /// When, which version and where the report came from.
        private var facts: String {
            let date = report.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
            return ([date] + [report.appVersion, report.source.title].compactMap(\.self)).joined(separator: " · ")
        }

        @ViewBuilder private var stackTrace: some View {
            let frames = StackFrame.frames(report.frames).map { $0.demangled(by: demangler) }
            let selected = frames.firstIndex { $0.isOwnCode(ownImage) }
            if frames.isEmpty {
                Text("No stack trace was recorded.")
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.secondary)
            } else {
                ForEach(Array(frames.enumerated()), id: \.offset) { position, frame in
                    DebugDrawerStackFrameRow(
                        index: frame.index,
                        symbol: frame.symbol,
                        image: frame.image,
                        isOwnCode: frame.isOwnCode(ownImage),
                        isSelected: position == selected
                    )
                }
            }
            DebugDrawerActionRow {
                DebugDrawerCopyButton("Copy Report") { report.text() }
            } trailing: {
                Button("Delete", role: .destructive, action: onDelete)
                    .debugDrawerButtonStyle(.destructive)
                    .accessibilityLabel("Delete report \(report.title)")
            }
        }
    }
#endif
