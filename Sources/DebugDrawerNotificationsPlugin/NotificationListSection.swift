#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The pending requests or the delivered notifications, newest first, each removable, and
    /// Remove All. It shows the newest few until Show All, so a center holding dozens leaves the
    /// rest of the plugin in reach; it keeps whether it shows them all.
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
        @State var showsAll = false
        let inspection = Inspection<Self>()

        /// How many rows the list shows until Show All. A cap rather than a lazy stack: the
        /// drawer lays a plugin's body out whole inside its scroll view, so a lazy stack here
        /// would still be as tall as every row, and dozens of rows are too many to look through.
        static let collapsedLimit = 5

        var body: some View {
            DebugDrawerSection("\(kind.title) (\(notifications.count))") {
                ForEach(visibleNotifications) { notification in
                    ListedNotificationRow(notification: notification, redaction: redaction) {
                        onRemove(notification.id)
                    }
                }
                if !notifications.isEmpty {
                    DebugDrawerActionRow {
                        if notifications.count > Self.collapsedLimit {
                            Button(showsAll ? "Show Newest \(Self.collapsedLimit)" : "Show All (\(notifications.count))") {
                                showsAll.toggle()
                            }
                            .debugDrawerButtonStyle(.borderless)
                            .accessibilityLabel(
                                showsAll
                                    ? "Show the newest \(Self.collapsedLimit) \(kind.title.lowercased()) notifications only"
                                    : "Show all \(notifications.count) \(kind.title.lowercased()) notifications"
                            )
                        }
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
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        /// Every notification newest first, or the newest few.
        var visibleNotifications: [ListedNotification] {
            let newestFirst = kind.newestFirst(notifications)
            return showsAll ? newestFirst : Array(newestFirst.prefix(Self.collapsedLimit))
        }
    }

    extension NotificationListSection.Kind {
        /// The notifications newest first: delivered ones by when they were delivered; pending
        /// ones in the reverse of the order the system lists them, which is the order they were
        /// added.
        fileprivate func newestFirst(_ notifications: [ListedNotification]) -> [ListedNotification] {
            switch self {
            case .pending:
                notifications.reversed()
            case .delivered:
                // Enumerated so equal dates keep the system's order: `sorted` isn't stable.
                notifications.enumerated()
                    .sorted { lhs, rhs in
                        let lhsDate = lhs.element.deliveredAt ?? .distantPast
                        let rhsDate = rhs.element.deliveredAt ?? .distantPast
                        return lhsDate == rhsDate ? lhs.offset < rhs.offset : lhsDate > rhsDate
                    }
                    .map(\.element)
            }
        }
    }
#endif
