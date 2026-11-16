#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The selected event below the list, at the drawer's full width: its name whole with a close
    /// button, its properties as inspector rows, its JSON at its natural height, and Copy JSON.
    /// Values the redaction rules call sensitive are masked in the copy, and on screen until
    /// revealed.
    struct AnalyticsEventDetail: View {
        let event: AnalyticsEvent
        let redaction: DebugDrawerRedaction
        let onClose: () -> Void
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone

        var body: some View {
            let redacted = event.redacted(by: redaction)
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerRow(event.name.breakableAtSeparators) {
                    Text(event.time(locale: locale, timeZone: timeZone))
                        .debugDrawerFont(.value)
                        .debugDrawerForegroundStyle(.tertiary)
                } accessory: {
                    Button(action: onClose) {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .debugDrawerButtonStyle(.borderless)
                    .accessibilityLabel("Close \(event.name)")
                }
                ForEach(event.sortedKeys, id: \.self) { key in
                    DebugDrawerKeyValueRow(
                        key,
                        value: event.properties[key]?.displayText ?? "",
                        redacted: redacted.properties[key]?.displayText,
                        labelWidth: 110
                    )
                }
                DebugDrawerCodeBlock {
                    // Long lines wrap, so the whole of each shows in the drawer's width.
                    RedactedText(event.formattedJSON, redacted: redacted.formattedJSON)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                DebugDrawerActionRow {
                    DebugDrawerCopyButton("Copy JSON") { redacted.formattedJSON }
                }
            }
        }
    }

    extension String {
        /// The text with a zero-width space after each `_`, `.`, `-`, `/` and `:`, so a wrapped
        /// name breaks there (`checkout_` / `completed`) rather than hyphenating inside a word.
        var breakableAtSeparators: String {
            reduce(into: "") { text, character in
                text.append(character)
                if "_.-/:".contains(character) {
                    text.append("\u{200B}")
                }
            }
        }
    }
#endif
