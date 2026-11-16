#if DEBUG
    /// Whether the drawer can ask the user for a permission now.
    enum PermissionRequest: Hashable, Sendable {
        /// Undecided, and the Info.plist declares what asking needs: the drawer offers Request.
        case available
        /// Asked; the system's prompt is up or its answer is on the way.
        case inProgress
        /// Undecided, but asking needs a key the Info.plist lacks: asking would crash the app or
        /// be ignored.
        case needsKey(String)
        /// Decided, or there's nothing to ask.
        case unavailable

        /// What the drawer can do for `permission` while its status is `status`.
        init(permission: DeclaredPermission, status: PermissionStatus, isRequesting: Bool) {
            if isRequesting {
                self = .inProgress
            } else if status != .notDetermined {
                self = .unavailable
            } else if let key = permission.missingRequestKey {
                self = .needsKey(key)
            } else {
                self = .available
            }
        }
    }

    extension DeclaredPermission {
        /// The key a request needs that the Info.plist doesn't declare, if any. Calendars and
        /// Reminders need the full-access (or, for calendars, write-only) keys of iOS 17 and
        /// macOS 14, as the legacy key alone no longer lets an app ask; Location asks for
        /// when-in-use access, which needs its own key (macOS also takes the legacy one).
        fileprivate var missingRequestKey: String? {
            switch kind {
            case .calendars:
                declares("NSCalendarsFullAccessUsageDescription") || declares("NSCalendarsWriteOnlyAccessUsageDescription")
                    ? nil : "NSCalendarsFullAccessUsageDescription"
            case .reminders:
                declares("NSRemindersFullAccessUsageDescription") ? nil : "NSRemindersFullAccessUsageDescription"
            case .location:
                declaresWhenInUseLocation ? nil : "NSLocationWhenInUseUsageDescription"
            default:
                nil
            }
        }

        private var declaresWhenInUseLocation: Bool {
            #if os(macOS)
                declares("NSLocationWhenInUseUsageDescription") || declares("NSLocationUsageDescription")
            #else
                declares("NSLocationWhenInUseUsageDescription")
            #endif
        }
    }
#endif
