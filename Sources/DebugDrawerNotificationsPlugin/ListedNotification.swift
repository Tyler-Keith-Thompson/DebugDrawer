#if DEBUG
    import DebugDrawer
    import Foundation

    /// A pending notification request or a delivered notification, as the drawer lists it.
    struct ListedNotification: Equatable, Identifiable, Sendable {
        /// The request's identifier, which removing it names.
        let id: String
        let title: String
        let subtitle: String
        let body: String
        let categoryIdentifier: String
        let threadIdentifier: String
        let badge: Int?
        /// What delivers it, or delivered it.
        let trigger: NotificationTrigger
        /// When it was delivered; `nil` while it is pending.
        let deliveredAt: Date?
        /// Its `userInfo`, as text.
        let userInfo: UserInfoText

        /// A notification with the given fields; the rest are empty, and it is pending, delivered
        /// at once.
        init(
            id: String,
            title: String = "",
            subtitle: String = "",
            body: String = "",
            categoryIdentifier: String = "",
            threadIdentifier: String = "",
            badge: Int? = nil,
            trigger: NotificationTrigger = .immediate,
            deliveredAt: Date? = nil,
            userInfo: UserInfoText = UserInfoText(text: "", isJSON: false)
        ) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.body = body
            self.categoryIdentifier = categoryIdentifier
            self.threadIdentifier = threadIdentifier
            self.badge = badge
            self.trigger = trigger
            self.deliveredAt = deliveredAt
            self.userInfo = userInfo
        }

        /// What the drawer names it by: its title, else its body, else its identifier.
        var displayName: String {
            [title, body].first { !$0.isEmpty } ?? id
        }

        /// `userInfo` with every value the rules call sensitive masked, pretty-printed again; text
        /// that isn't JSON is masked whole whenever the rules mask any key, since its keys can't be
        /// told apart from its values.
        func redactedUserInfo(_ redaction: DebugDrawerRedaction) -> String {
            let text = userInfo.text
            guard !text.isEmpty else { return text }
            guard userInfo.isJSON else {
                return redaction.keyPatterns.isEmpty && redaction.jsonPaths.isEmpty ? text : DebugDrawerRedaction.mask
            }
            let original = Data(text.utf8)
            let redacted = redaction.redacting(json: original)
            guard redacted != original,
                  let object = try? JSONSerialization.jsonObject(with: redacted),
                  let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]),
                  let prettyText = String(bytes: pretty, encoding: .utf8)
            else { return text }
            return prettyText
        }
    }
#endif
