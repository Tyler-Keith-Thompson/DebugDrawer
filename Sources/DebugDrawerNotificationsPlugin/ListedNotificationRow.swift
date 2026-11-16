#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One pending or delivered notification: its title, subtitle and body, its identifier, what
    /// delivers it or when it was delivered, its category, thread and badge, its `userInfo`, and
    /// a button that removes it.
    struct ListedNotificationRow: View {
        let notification: ListedNotification
        let redaction: DebugDrawerRedaction
        let onRemove: () -> Void
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone
        /// The tallest `userInfo` gets before it scrolls: a payload runs to 4 KB.
        @ScaledMetric(relativeTo: .caption2) private var userInfoHeight: CGFloat = 160

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    content
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .combine)
                    Button(action: onRemove) {
                        Label("Remove", systemImage: "trash")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .accessibilityLabel("Remove \(notification.displayName)")
                }
                if !notification.userInfo.text.isEmpty {
                    userInfo
                }
            }
            .padding(.vertical, 2)
        }

        private var content: some View {
            VStack(alignment: .leading, spacing: 2) {
                if !notification.title.isEmpty {
                    Text(notification.title)
                        .font(.caption.weight(.semibold))
                }
                if !notification.subtitle.isEmpty {
                    Text(notification.subtitle)
                        .font(.caption)
                }
                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(notification.id)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Text(details)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        /// When it was delivered, or what delivers it; then its category, thread and badge.
        private var details: String {
            let when: String
            if let deliveredAt = notification.deliveredAt {
                var style = Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale)
                style.timeZone = timeZone
                when = "Delivered \(deliveredAt.formatted(style))"
            } else {
                when = notification.trigger.text(locale: locale, timeZone: timeZone)
            }
            let category = notification.categoryIdentifier.isEmpty ? [] : ["category \(notification.categoryIdentifier)"]
            let thread = notification.threadIdentifier.isEmpty ? [] : ["thread \(notification.threadIdentifier)"]
            let badge = notification.badge.map { ["badge \($0)"] } ?? []
            return ([when] + category + thread + badge).joined(separator: " · ")
        }

        private var userInfo: some View {
            ScrollView([.horizontal, .vertical]) {
                RedactedText(notification.userInfo.text, redacted: notification.redactedUserInfo(redaction))
                    .font(.system(.caption2, design: .monospaced))
                    .fixedSize()
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: userInfoHeight)
            .fixedSize(horizontal: false, vertical: true)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 4))
        }
    }
#endif
