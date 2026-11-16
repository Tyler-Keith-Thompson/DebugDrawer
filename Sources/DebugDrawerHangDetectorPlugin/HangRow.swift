#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One hang: how long, when and where from, a New tag until it is opened, and, open, its
    /// stack with a button that copies the whole hang.
    struct HangRow: View {
        let event: HangEvent
        let isExpanded: Bool
        let onToggle: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone
        @ScaledMetric(relativeTo: .caption2) private var chevronWidth: CGFloat = 10

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                Button(action: onToggle) {
                    summary
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(isExpanded ? "Hides the stack" : "Shows the stack")
                if isExpanded {
                    stack
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
                    Text(facts)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        /// The duration and, until the hang is opened, a New tag: side by side, or one above the
        /// other at accessibility text sizes.
        private var titleLine: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
            return layout {
                Text(event.durationText)
                    .font(.system(.caption, design: .monospaced).weight(.semibold))
                    .accessibilityLabel("Hung for \(event.durationText)")
                if !event.isSeen {
                    Text("New")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                        .accessibilityLabel("New hang")
                }
            }
        }

        /// When it began and where it came from.
        private var facts: String {
            let date = event.date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: timeZone))
            return "\(date) · \(event.source.title)"
        }

        private var stack: some View {
            VStack(alignment: .leading, spacing: 6) {
                if event.frames.isEmpty {
                    Text(HangEvent.noStack)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ScrollView(.horizontal) {
                        Text(event.frames.joined(separator: "\n"))
                            .font(.system(.caption2, design: .monospaced))
                            .textSelection(.enabled)
                            .fixedSize()
                            .padding(6)
                    }
                    .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
                }
                DebugDrawerCopyButton("Copy Report") { event.text() }
            }
        }
    }
#endif
