#if DEBUG
    /// The activity of the app's own type the form is composing: its type and its userInfo rows.
    struct ActivityDraft: Hashable {
        /// Whether the draft can be sent, and if not, why.
        enum Validation: Equatable {
            /// It can be sent as this activity.
            case ready(DeepLinkActivity)
            /// The type is still empty; nothing needs saying.
            case incomplete
            /// A row is wrong, in words ("“count” isn't a number").
            case invalid(String)
        }

        var activityType: String
        var fields: [UserInfoField]

        init(activityType: String = "", fields: [UserInfoField] = []) {
            self.activityType = activityType
            self.fields = fields
        }

        /// The draft that edits `activity`.
        init(_ activity: DeepLinkActivity) {
            self.init(activityType: activity.activityType, fields: activity.userInfo.map(UserInfoField.init))
        }

        var validation: Validation {
            let type = activityType.trimmingCharacters(in: .whitespaces)
            guard !type.isEmpty else { return .incomplete }
            var entries: [UserInfoEntry] = []
            for field in fields {
                guard !field.key.isEmpty else { return .invalid("A row has no key") }
                guard !entries.contains(where: { $0.key == field.key }) else { return .invalid("“\(field.key)” is used twice") }
                guard let value = field.value else { return .invalid("“\(field.key)” isn't a number") }
                entries.append(UserInfoEntry(key: field.key, value: value))
            }
            return .ready(DeepLinkActivity(activityType: type, webpageURL: nil, userInfo: entries))
        }
    }
#endif
