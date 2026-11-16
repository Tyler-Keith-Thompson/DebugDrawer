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
        @ScaledMetric(relativeTo: .body) private var userInfoHeight: CGFloat = 160

        var body: some View {
            DebugDrawerRow(notification.displayName, systemImage: notification.deliveredAt == nil ? "clock" : "bell") {
                content
                if !notification.userInfo.text.isEmpty {
                    userInfo
                }
            } accessory: {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .debugDrawerButtonStyle(.borderless)
                .accessibilityLabel("Remove \(notification.displayName)")
            }
        }

        /// The subtitle, the body when the title names the row, the identifier and the details.
        @ViewBuilder private var content: some View {
            if !notification.subtitle.isEmpty {
                Text(notification.subtitle)
            }
            if !notification.title.isEmpty, !notification.body.isEmpty {
                Text(notification.body)
            }
            DebugDrawerCodeText(notification.id)
            Text(details)
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
            DebugDrawerCodeBlock {
                ScrollView([.horizontal, .vertical]) {
                    RedactedText(notification.userInfo.text, redacted: notification.redactedUserInfo(redaction))
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: userInfoHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
#endif
