#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One pending or delivered notification on one line: its name and when it was delivered or
    /// fires, with a button that removes it. Tapping the name opens it to its subtitle and body,
    /// its identifier, what delivers it or when it was delivered, its category, thread and badge,
    /// and its `userInfo`. It keeps whether it is open.
    struct ListedNotificationRow: View {
        let notification: ListedNotification
        let redaction: DebugDrawerRedaction
        let onRemove: () -> Void
        @State var isExpanded = false
        let inspection = Inspection<Self>()
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        /// The tallest `userInfo` gets before it scrolls: a payload runs to 4 KB.
        @ScaledMetric(relativeTo: .body) private var userInfoHeight: CGFloat = 160

        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                if dynamicTypeSize.isAccessibilitySize {
                    HStack(alignment: .firstTextBaseline) {
                        expandButton
                        Spacer()
                        removeButton
                    }
                    time
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        expandButton
                        Spacer()
                        time
                        removeButton
                    }
                }
                if isExpanded {
                    details
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, 16)
                }
            }
            .debugDrawerRowPadding()
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        private var expandButton: some View {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Image(systemName: notification.deliveredAt == nil ? "clock" : "bell")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .accessibilityHidden(true)
                    // One line until opened; VoiceOver reads it whole. At accessibility sizes it
                    // wraps whole, since one line holds a word or two there.
                    Text(notification.displayName)
                        .debugDrawerFont(.body)
                        .debugDrawerForegroundStyle(.primary)
                        .lineLimit(isExpanded || dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .multilineTextAlignment(.leading)
                        .help(notification.displayName)
                }
            }
            .debugDrawerButtonStyle(.plain)
            .accessibilityLabel(notification.displayName)
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        }

        /// When it was delivered, or when it fires next, as a clock time; what delivers it when
        /// the system doesn't say when.
        private var time: some View {
            Text(notification.timeText(locale: locale, timeZone: timeZone))
                .debugDrawerFont(.value)
                .debugDrawerForegroundStyle(.tertiary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        }

        private var removeButton: some View {
            Button(role: .destructive, action: onRemove) {
                Label("Remove", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .debugDrawerButtonStyle(.borderless)
            .accessibilityLabel("Remove \(notification.displayName)")
        }

        /// The subtitle, the body when the title names the row, the identifier, the details and
        /// the `userInfo`.
        @ViewBuilder private var details: some View {
            if !notification.subtitle.isEmpty {
                Text(notification.subtitle)
            }
            if !notification.title.isEmpty, !notification.body.isEmpty {
                Text(notification.body)
            }
            DebugDrawerCodeText(notification.id)
            Text(notification.detailsText(locale: locale, timeZone: timeZone))
            if !notification.userInfo.text.isEmpty {
                userInfo
            }
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

    extension ListedNotification {
        /// The row's clock time: when it was delivered, or when it fires next; what delivers it
        /// when the system doesn't say when.
        fileprivate func timeText(locale: Locale, timeZone: TimeZone) -> String {
            var style = Date.FormatStyle(date: .omitted, time: .standard, locale: locale)
            style.timeZone = timeZone
            if let deliveredAt {
                return deliveredAt.formatted(style)
            }
            switch trigger {
            case let .timeInterval(_, _, next?), let .calendar(_, _, next?):
                return next.formatted(style)
            case .immediate, .timeInterval, .calendar, .location, .push, .other:
                return trigger.text(locale: locale, timeZone: timeZone)
            }
        }

        /// When it was delivered, or what delivers it; then its category, thread and badge.
        fileprivate func detailsText(locale: Locale, timeZone: TimeZone) -> String {
            let when: String
            if let deliveredAt {
                var style = Date.FormatStyle(date: .abbreviated, time: .standard, locale: locale)
                style.timeZone = timeZone
                when = "Delivered \(deliveredAt.formatted(style))"
            } else {
                when = trigger.text(locale: locale, timeZone: timeZone)
            }
            let category = categoryIdentifier.isEmpty ? [] : ["category \(categoryIdentifier)"]
            let thread = threadIdentifier.isEmpty ? [] : ["thread \(threadIdentifier)"]
            let badge = badge.map { ["badge \($0)"] } ?? []
            return ([when] + category + thread + badge).joined(separator: " · ")
        }
    }
#endif
