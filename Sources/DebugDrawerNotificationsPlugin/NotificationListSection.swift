#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The pending requests or the delivered notifications, each removable, and Remove All.
    struct NotificationListSection: View {
        /// Which list this is.
        enum Kind {
            case pending
            case delivered

            var title: String {
                switch self {
                case .pending: "Pending"
                case .delivered: "Delivered"
                }
            }

            var emptyText: String {
                switch self {
                case .pending: "No pending notifications."
                case .delivered: "No delivered notifications in Notification Center."
                }
            }
        }

        let kind: Kind
        let notifications: [ListedNotification]
        let redaction: DebugDrawerRedaction
        let onRemove: (ListedNotification.ID) -> Void
        let onRemoveAll: () -> Void

        var body: some View {
            DebugDrawerSection("\(kind.title) (\(notifications.count))") {
                ForEach(notifications) { notification in
                    ListedNotificationRow(notification: notification, redaction: redaction) {
                        onRemove(notification.id)
                    }
                }
                if !notifications.isEmpty {
                    DebugDrawerActionRow {
                        EmptyView()
                    } trailing: {
                        Button("Remove All", role: .destructive, action: onRemoveAll)
                            .debugDrawerButtonStyle(.destructive)
                            .accessibilityLabel("Remove all \(kind.title.lowercased()) notifications")
                    }
                }
            } footer: {
                if notifications.isEmpty {
                    Text(kind.emptyText)
                }
            }
        }
    }
#endif
