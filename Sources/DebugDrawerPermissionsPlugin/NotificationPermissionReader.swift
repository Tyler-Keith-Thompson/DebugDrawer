#if DEBUG
    import UserNotifications

    /// Notifications, through User Notifications. Asks for alerts, badges and sounds.
    struct NotificationPermissionReader: SystemPermissionReader {
        func status(of _: DeclaredPermission) async -> PermissionStatus {
            await PermissionStatus(UNUserNotificationCenter.current().notificationSettings().authorizationStatus)
        }

        func request(_: DeclaredPermission) async {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        }
    }

    extension PermissionStatus {
        init(_ status: UNAuthorizationStatus) {
            switch status {
            case .notDetermined: self = .notDetermined
            case .denied: self = .denied
            case .authorized: self = .authorized
            case .provisional: self = .provisional
            #if os(iOS)
                case .ephemeral: self = .ephemeral
            #endif
            @unknown default: self = .unknown(rawValue: status.rawValue)
            }
        }
    }
#endif
