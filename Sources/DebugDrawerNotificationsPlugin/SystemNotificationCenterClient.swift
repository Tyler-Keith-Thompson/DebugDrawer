#if DEBUG
    import DebugDrawerNotifications
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
#endif
