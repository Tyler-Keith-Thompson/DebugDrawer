#if DEBUG
    /// The app's notification settings, as the system reported them: whether it may notify, and
    /// how each kind of presentation is set.
    struct NotificationSettings: Equatable, Sendable {
        /// Whether the app may post notifications.
        enum Authorization: Equatable, Sendable {
            case notDetermined
            case denied
            case authorized
            /// Delivered quietly to Notification Center until the user decides.
            case provisional
            /// An App Clip's, for a limited time.
            case ephemeral
            /// A status this build doesn't know, by its raw value.
            case unknown(rawValue: Int)

            var title: String {
                switch self {
                case .notDetermined: "Not Asked"
                case .denied: "Denied"
                case .authorized: "Allowed"
                case .provisional: "Provisional"
                case .ephemeral: "Ephemeral"
                case let .unknown(rawValue): "Unknown (\(rawValue))"
                }
            }
        }

        /// How one kind of presentation is set.
        enum Setting: Equatable, Sendable {
            case notSupported
            case disabled
            case enabled
            case unknown(rawValue: Int)

            var title: String {
                switch self {
                case .notSupported: "Not Supported"
                case .disabled: "Off"
                case .enabled: "On"
                case let .unknown(rawValue): "Unknown (\(rawValue))"
                }
            }
        }

        /// One named setting, in the order the drawer lists them.
        struct Item: Equatable, Sendable {
            let name: String
            let value: String
        }

        let authorization: Authorization
        /// Each presentation setting the platform reports (Alerts, Sounds, Badges and so on), with
        /// the alert style and when previews show.
        let items: [Item]
    }
#endif
