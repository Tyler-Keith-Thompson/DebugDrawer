#if DEBUG
    import DebugDrawer
    import Foundation

    extension NotificationsPlugin: DebugDrawerReportContributor {
        /// Adds `notifications.txt`: the device token, the authorization and settings, and every
        /// pending and delivered notification, as last read.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            Self.contribute(registration: model.registration, center: model.center, redaction: redaction, to: &report)
        }

        /// Adds the state as `notifications.txt`. The token is a device identifier, so it is
        /// redacted under its key as the drawer's rules say (the standard rules mask it), as is
        /// every sensitive value in a `userInfo`; times are in UTC.
        static func contribute(
            registration: RemoteRegistration, center: NotificationCenterState, redaction: DebugDrawerRedaction, to report: inout DebugDrawerReport
        ) {
            report.add(text: text(registration: registration, center: center, redaction: redaction), named: "notifications.txt")
        }

        static func text(registration: RemoteRegistration, center: NotificationCenterState, redaction: DebugDrawerRedaction) -> String {
            let token = switch registration {
            case .notRegistered: "APNs device token: none reported"
            case let .registered(deviceToken):
                "APNs device token: \(redaction.redacting(deviceToken.hexadecimal, forKey: RemoteRegistration.redactionKey))"
            case let .failed(message): "APNs registration failed: \(message)"
            }
            guard case let .loaded(snapshot) = center else {
                return [token, "Notification center: not read yet"].joined(separator: "\n")
            }
            let settings = ["Authorization: \(snapshot.settings.authorization.title)"]
                + snapshot.settings.items.map { "  \($0.name): \($0.value)" }
            return ([token] + settings
                + list("Pending", snapshot.pending, redaction: redaction)
                + list("Delivered", snapshot.delivered, redaction: redaction))
                .joined(separator: "\n")
        }

        private static func list(_ title: String, _ notifications: [ListedNotification], redaction: DebugDrawerRedaction) -> [String] {
            ["\(title) (\(notifications.count)):"] + notifications.flatMap { $0.reportLines(redaction: redaction) }
        }
    }

    extension ListedNotification {
        /// Its identifier, then each field it has, indented, and its `userInfo` indented below.
        fileprivate func reportLines(redaction: DebugDrawerRedaction) -> [String] {
            let posix = Locale(identifier: "en_US_POSIX")
            let timeZone = TimeZone.gmt
            let when = deliveredAt.map { "delivered: \($0.formatted(.iso8601))" }
                ?? "trigger: \(trigger.text(locale: posix, timeZone: timeZone))"
            let fields: [(String, String)] = [
                ("title", title), ("subtitle", subtitle), ("body", body),
                ("category", categoryIdentifier), ("thread", threadIdentifier), ("badge", badge.map(String.init) ?? "")
            ]
            let userInfo = redactedUserInfo(redaction)
            return ["  \(id)", "    \(when)"]
                + fields.filter { !$0.1.isEmpty }.map { "    \($0.0): \($0.1)" }
                + (userInfo.isEmpty ? [] : ["    userInfo:"] + userInfo.split(separator: "\n").map { "      \($0)" })
        }
    }
#endif
