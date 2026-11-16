#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One report: what crashed, when and in which version, a New tag until it is opened, and,
    /// open, its stack trace with a button that copies the whole report.
    struct CrashReportRow: View {
        let report: CrashReport
        let isExpanded: Bool
        let onToggle: () -> Void
        let onDelete: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone
        @ScaledMetric(relativeTo: .caption2) private var chevronWidth: CGFloat = 10

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Button(action: onToggle) {
                        summary
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                    .accessibilityHint(isExpanded ? "Hides the stack trace" : "Shows the stack trace")
                    Button(action: onDelete) {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("Delete report \(report.title)")
                }
                if isExpanded {
                    stackTrace
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
        }

        private var summary: some View {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                // One width for both chevrons, so open and closed rows line up.
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: chevronWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    titleLine
                    if let reason = report.reason {
                        Text(reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(isExpanded ? nil : 2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(facts)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        /// The title and, until the report is opened, a New tag: side by side, or one above the
        /// other at accessibility text sizes.
        private var titleLine: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
            return layout {
                Text(report.title)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                if !report.isSeen {
                    Text("New")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                        .accessibilityLabel("New report")
                }
            }
        }

        /// When, which version and where the report came from.
        private var facts: String {
            let date = report.date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
            return ([date] + [report.appVersion, report.source.title].compactMap(\.self)).joined(separator: " · ")
        }

        private var stackTrace: some View {
            VStack(alignment: .leading, spacing: 6) {
                if report.frames.isEmpty {
                    Text("No stack trace was recorded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView(.horizontal) {
                        Text(report.frames.joined(separator: "\n"))
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize()
                            .padding(6)
                    }
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                }
                DebugDrawerCopyButton("Copy Report") { report.text() }
            }
        }
    }
#endif
