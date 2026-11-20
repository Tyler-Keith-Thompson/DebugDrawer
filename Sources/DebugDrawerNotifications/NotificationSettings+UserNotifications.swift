import Foundation
import UserNotifications

// User Notifications' settings mapped into the module's own types, for the Notifications plugin's
// notification center client and the push registration capability alike, so neither shows the
// framework's types to the rest of its code.

extension NotificationSettings {
    /// The app's notification settings now, from User Notifications' current center.
    ///
    /// The center exists only in an app with a bundle identifier; a test runner has none, so tests
    /// hand the capability settings of their own.
    @MainActor
    package static func current() async -> NotificationSettings {
        await NotificationSettings(UNUserNotificationCenter.current().notificationSettings())
    }

    /// `settings` in the module's own terms.
    package init(_ settings: UNNotificationSettings) {
        var items = [
            Item(name: "Alerts", value: Setting(settings.alertSetting).title),
            Item(name: "Sounds", value: Setting(settings.soundSetting).title),
            Item(name: "Badges", value: Setting(settings.badgeSetting).title),
            Item(name: "Lock Screen", value: Setting(settings.lockScreenSetting).title),
            Item(name: "Notification Center", value: Setting(settings.notificationCenterSetting).title)
        ]
        #if os(iOS)
            items.append(Item(name: "CarPlay", value: Setting(settings.carPlaySetting).title))
        #endif
        items += [
            Item(name: "Critical Alerts", value: Setting(settings.criticalAlertSetting).title),
            Item(name: "Time Sensitive", value: Setting(settings.timeSensitiveSetting).title),
            Item(name: "Scheduled Summary", value: Setting(settings.scheduledDeliverySetting).title),
            Item(name: "Alert Style", value: settings.alertStyle.title),
            Item(name: "Previews", value: settings.showPreviewsSetting.title)
        ]
        self.init(authorization: Authorization(settings.authorizationStatus), items: items)
    }
}

extension NotificationSettings.Authorization {
    package init(_ status: UNAuthorizationStatus) {
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

extension NotificationSettings.Setting {
    package init(_ setting: UNNotificationSetting) {
        switch setting {
        case .notSupported: self = .notSupported
        case .disabled: self = .disabled
        case .enabled: self = .enabled
        @unknown default: self = .unknown(rawValue: setting.rawValue)
        }
    }
}

extension UNAlertStyle {
    fileprivate var title: String {
        switch self {
        case .none: "None"
        case .banner: "Banners"
        case .alert: "Alerts"
        @unknown default: "Unknown (\(rawValue))"
        }
    }
}

extension UNShowPreviewsSetting {
    fileprivate var title: String {
        switch self {
        case .always: "Always"
        case .whenAuthenticated: "When Unlocked"
        case .never: "Never"
        @unknown default: "Unknown (\(rawValue))"
        }
    }
}
