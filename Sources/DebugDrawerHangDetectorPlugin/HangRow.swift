#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One hang as an issue row: a warning glyph, how long, when and where from, an unread dot
    /// until it is opened, and, open, its stack as the debug navigator shows one (the app's own
    /// frames badged, the first of them selected), with a button that copies the whole hang.
    struct HangRow: View {
        let event: HangEvent
        let isExpanded: Bool
        /// The app's executable's file name, which marks the app's own frames.
        var ownImage: String?
        /// Names the frames' Swift symbols as Xcode does; Copy Report still copies them as recorded.
        let demangler: any SymbolDemangler
        let onToggle: () -> Void
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onToggle) {
                    DebugDrawerIssueRow(event.durationText, severity: .warning) {
                        Text(facts)
                    } accessory: {
                        HStack(spacing: 6) {
                            if !event.isSeen {
                                DebugDrawerUnreadDot()
                                    .accessibilityLabel("New hang")
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
                .accessibilityLabel("Hung for \(event.durationText)")
                .accessibilityValue(event.isSeen ? facts : "New hang, \(facts)")
                .accessibilityHint(isExpanded ? "Hides the stack" : "Shows the stack")
                if isExpanded {
                    stack
                }
            }
        }

        /// When it began and where it came from.
        private var facts: String {
            let date = event.date.formatted(Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale, timeZone: timeZone))
            return "\(date) · \(event.source.title)"
        }

        @ViewBuilder private var stack: some View {
            let frames = StackFrame.frames(event.frames).map { $0.demangled(by: demangler) }
            let selected = frames.firstIndex { $0.isOwnCode(ownImage) }
            if frames.isEmpty {
                Text(HangEvent.noStack)
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                DebugDrawerCopyButton("Copy Report") { event.text() }
            }
        }
    }
#endif
