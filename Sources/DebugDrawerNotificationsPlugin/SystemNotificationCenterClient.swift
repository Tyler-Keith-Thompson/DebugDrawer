#if DEBUG
    import Foundation
    import UserNotifications

    /// User Notifications' current notification center. Every value it hands back is mapped into
    /// the plugin's own types here, so the rest of the plugin imports nothing of the framework.
    struct SystemNotificationCenterClient: NotificationCenterClient {
        private var center: UNUserNotificationCenter {
            .current()
        }

        func settings() async -> NotificationSettings {
            await NotificationSettings(center.notificationSettings())
        }

        func requestAuthorization() async throws(NotificationCenterFailure) {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .badge, .sound])
            } catch {
                throw NotificationCenterFailure(message: error.localizedDescription)
            }
        }

        func pendingNotifications() async -> [ListedNotification] {
            await center.pendingNotificationRequests().map { ListedNotification($0, deliveredAt: nil) }
        }

        func deliveredNotifications() async -> [ListedNotification] {
            await center.deliveredNotifications().map { ListedNotification($0.request, deliveredAt: $0.date) }
        }

        func add(_ payload: NotificationPayload, identifier: String, delay: SendDelay) async throws(NotificationCenterFailure) {
            let trigger = delay.seconds.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
            let request = UNNotificationRequest(identifier: identifier, content: UNMutableNotificationContent(payload), trigger: trigger)
            do {
                try await center.add(request)
            } catch {
                throw NotificationCenterFailure(message: error.localizedDescription)
            }
        }

        func removePendingNotifications(withIdentifiers identifiers: [String]) {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }

        func removeAllPendingNotifications() {
            center.removeAllPendingNotificationRequests()
        }

        func removeDeliveredNotifications(withIdentifiers identifiers: [String]) {
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }

        func removeAllDeliveredNotifications() {
            center.removeAllDeliveredNotifications()
        }
    }

    extension ListedNotification {
        fileprivate init(_ request: UNNotificationRequest, deliveredAt: Date?) {
            let content = request.content
            self.init(
                id: request.identifier,
                title: content.title,
                subtitle: content.subtitle,
                body: content.body,
                categoryIdentifier: content.categoryIdentifier,
                threadIdentifier: content.threadIdentifier,
                badge: content.badge?.intValue,
                trigger: NotificationTrigger(request.trigger),
                deliveredAt: deliveredAt,
                userInfo: UserInfoText(content.userInfo)
            )
        }
    }

    extension NotificationTrigger {
        init(_ trigger: UNNotificationTrigger?) {
            switch trigger {
            case nil:
                self = .immediate
            case let interval as UNTimeIntervalNotificationTrigger:
                self = .timeInterval(seconds: interval.timeInterval, repeats: interval.repeats, next: interval.nextTriggerDate())
            case let calendar as UNCalendarNotificationTrigger:
                self = .calendar(calendar.dateComponents, repeats: calendar.repeats, next: calendar.nextTriggerDate())
            case is UNPushNotificationTrigger:
                self = .push
            case let trigger?:
                #if os(iOS) && !targetEnvironment(macCatalyst)
                    if let location = trigger as? UNLocationNotificationTrigger {
                        self = .location(region: location.region.identifier, repeats: location.repeats)
                        return
                    }
                #endif
                self = .other(String(describing: type(of: trigger)))
            }
        }
    }

    extension NotificationSettings {
        init(_ settings: UNNotificationSettings) {
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

    extension NotificationSettings.Setting {
        init(_ setting: UNNotificationSetting) {
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
#endif
