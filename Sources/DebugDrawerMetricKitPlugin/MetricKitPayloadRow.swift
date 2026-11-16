#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One payload: its kind, what it holds and the period it covers, a New tag until it is
    /// opened, and, open, its formatted JSON with buttons that copy and export it.
    struct MetricKitPayloadRow: View {
        let payload: MetricKitPayload
        let isExpanded: Bool
        let onToggle: () -> Void
        let onDelete: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone
        @ScaledMetric(relativeTo: .caption2) private var chevronWidth: CGFloat = 10
        /// The tallest the JSON gets before it scrolls: a day's metrics run to hundreds of lines.
        @ScaledMetric(relativeTo: .caption2) private var jsonHeight: CGFloat = 280

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
                    .accessibilityHint(isExpanded ? "Hides the JSON" : "Shows the JSON")
                    Button(action: onDelete) {
                        Label("Delete", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("Delete \(payload.kind.title.lowercased()) payload of \(period)")
                }
                if isExpanded {
                    json
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
                    Text(payload.summary.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(period)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        /// The kind and, until the payload is opened, a New tag: side by side, or one above the
        /// other at accessibility text sizes.
        private var titleLine: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
            return layout {
                Text(payload.kind.title)
                    .font(.caption.weight(.semibold))
                if !payload.isSeen {
                    Text("New")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.red)
                        .accessibilityLabel("New payload")
                }
            }
        }

        /// The period the payload covers, in the view's locale and time zone.
        private var period: String {
            payload.period.formatted(Date.IntervalFormatStyle(date: .abbreviated, time: .shortened, locale: locale, timeZone: timeZone))
        }

        private var json: some View {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView([.horizontal, .vertical]) {
                    Text(payload.formattedJSON)
                        .font(.system(.caption2, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize()
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: jsonHeight)
                .fixedSize(horizontal: false, vertical: true)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                buttons
            }
        }

        /// Copy JSON and Export: side by side, or one above the other at accessibility text sizes.
        private var buttons: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout())
            return layout {
                DebugDrawerCopyButton("Copy JSON") { payload.formattedJSON }
                ShareLink(
                    item: MetricKitPayloadFile(payload: payload),
                    preview: SharePreview(payload.exportFileName)
                ) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Export the payload as a JSON file")
            }
        }
    }
#endif
