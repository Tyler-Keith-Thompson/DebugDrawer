#if DEBUG
    /// What the system says about a permission, mapped from each framework's own status type.
    enum PermissionStatus: Hashable, Sendable {
        /// Not read yet.
        case checking
        /// The user hasn't been asked.
        case notDetermined
        case authorized
        /// Location, at any time.
        case authorizedAlways
        /// Location, while the app is in use.
        case authorizedWhenInUse
        /// Some of what was asked for: chosen photos or contacts.
        case limited
        /// Calendars: adding events, not reading them.
        case writeOnly
        /// Notifications delivered quietly, until the user decides.
        case provisional
        /// Notifications for an App Clip, for a limited time.
        case ephemeral
        case denied
        /// Not the user's to give: parental controls or a device policy.
        case restricted
        /// The system has no API that reads it (local network).
        case noStatusAPI
        /// The plugin has no reader for it.
        case notChecked
        /// This platform doesn't have it.
        case unavailable
        /// A status newer than the plugin, by the framework's raw value.
        case unknown(rawValue: Int)

        var title: String {
            switch self {
            case .checking: "Checking…"
            case .notDetermined: "Not Asked"
            case .authorized: "Allowed"
            case .authorizedAlways: "Always"
            case .authorizedWhenInUse: "While Using"
            case .limited: "Limited"
            case .writeOnly: "Add Events Only"
            case .provisional: "Provisional"
            case .ephemeral: "Ephemeral"
            case .denied: "Denied"
            case .restricted: "Restricted"
            case .noStatusAPI: "No Status API"
            case .notChecked: "Not Checked"
            case .unavailable: "Not on This Platform"
            case let .unknown(rawValue): "Unknown (\(rawValue))"
            }
        }

        /// What the status means for the app, for the row's caption.
        var explanation: String? {
            switch self {
            case .noStatusAPI: "Declared. The system reports no status for it, so the plugin can't read one."
            case .notChecked: "Declared. The plugin doesn't read this permission's status."
            case .unavailable: "Declared, but this platform has no such permission."
            case .restricted: "Parental controls or a device policy decide this; the user can't change it."
            default: nil
            }
        }

        /// How far the status lets the app go, which picks its symbol and color.
        var grant: Grant {
            switch self {
            case .authorized, .authorizedAlways, .authorizedWhenInUse: .granted
            case .limited, .writeOnly, .provisional, .ephemeral: .partial
            case .denied, .restricted: .refused
            case .notDetermined: .undecided
            case .checking, .noStatusAPI, .notChecked, .unavailable, .unknown: .unknown
            }
        }

        enum Grant {
            case granted, partial, refused, undecided, unknown

            /// An SF Symbol, distinct per grant, so the status reads without its color.
            var symbol: String {
                switch self {
                case .granted: "checkmark.circle.fill"
                case .partial: "circle.lefthalf.filled"
                case .refused: "xmark.circle.fill"
                case .undecided: "questionmark.circle"
                case .unknown: "minus.circle"
                }
            }
        }
    }
#endif
