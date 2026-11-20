// The settings live here rather than in the Notifications plugin because the push registration
// capability serves them to a sidecar from a release build, which links this module and not the
// plugin; the plugin re-exports the module and draws the same values. Each presentation setting is
// carried as the name and value the drawer shows, since the sidecar shows them the same way and
// the platforms report different sets (CarPlay on iOS only).

/// The app's notification settings, as the system reported them: whether it may notify, and how
/// each kind of presentation is set.
public struct NotificationSettings: Codable, Equatable, Sendable {
    /// Whether the app may post notifications.
    public enum Authorization: Codable, Equatable, Sendable {
        /// The user hasn't been asked.
        case notDetermined
        /// The user turned notifications off.
        case denied
        /// The app may notify.
        case authorized
        /// Delivered quietly to Notification Center until the user decides.
        case provisional
        /// An App Clip's, for a limited time.
        case ephemeral
        /// A status this build doesn't know, by its raw value.
        case unknown(rawValue: Int)

        /// The status as the drawer and a sidecar name it.
        public var title: String {
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
    public enum Setting: Codable, Equatable, Sendable {
        /// The app's configuration doesn't offer it.
        case notSupported
        /// The user turned it off.
        case disabled
        /// It is on.
        case enabled
        /// A setting this build doesn't know, by its raw value.
        case unknown(rawValue: Int)

        /// The setting as the drawer and a sidecar name it.
        public var title: String {
            switch self {
            case .notSupported: "Not Supported"
            case .disabled: "Off"
            case .enabled: "On"
            case let .unknown(rawValue): "Unknown (\(rawValue))"
            }
        }
    }

    /// One named setting, in the order the drawer lists them.
    public struct Item: Codable, Equatable, Sendable {
        /// What it sets, such as "Alerts".
        public let name: String
        /// How it is set, such as "On".
        public let value: String

        /// A named setting.
        ///
        /// - Parameters:
        ///   - name: What it sets.
        ///   - value: How it is set.
        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }

    /// Whether the app may notify.
    public let authorization: Authorization
    /// Each presentation setting the platform reports (Alerts, Sounds, Badges and so on), with the
    /// alert style and when previews show.
    public let items: [Item]

    /// Settings as the system reported them.
    ///
    /// - Parameters:
    ///   - authorization: Whether the app may notify.
    ///   - items: Each presentation setting, in the order they are listed.
    public init(authorization: Authorization, items: [Item]) {
        self.authorization = authorization
        self.items = items
    }
}
