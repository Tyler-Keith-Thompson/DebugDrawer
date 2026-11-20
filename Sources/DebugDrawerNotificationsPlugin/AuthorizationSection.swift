#if DEBUG
    import DebugDrawer
    import DebugDrawerNotifications
    import SwiftUI

    /// Whether the app may notify, as an issue row, each presentation setting, Request while the
    /// user hasn't decided, and Refresh.
    struct AuthorizationSection: View {
        let settings: NotificationSettings
        let request: AuthorizationRequestState
        let onRequest: () -> Void
        let onRefresh: () -> Void

        var body: some View {
            DebugDrawerSection("Authorization") {
                DebugDrawerIssueRow("Notifications", status: settings.authorization.title, severity: settings.authorization.severity) {
                    if case let .failed(message) = request {
                        Text("Asking failed: \(message)")
                    }
                }
                ForEach(settings.items, id: \.name) { item in
                    DebugDrawerKeyValueRow(item.name, value: item.value, labelWidth: 120)
                }
                buttons
            }
        }

        /// Request, while it can be asked for, and Refresh.
        private var buttons: some View {
            DebugDrawerActionRow {
                if settings.authorization == .notDetermined {
                    if request == .requesting {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Asking…")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Asking for notification access")
                    } else {
                        Button("Request", action: onRequest)
                            .debugDrawerButtonStyle(.primary)
                            .accessibilityLabel("Request notification access")
                            .accessibilityHint("Shows the system's prompt")
                    }
                }
                Button("Refresh", action: onRefresh)
                    .accessibilityLabel("Refresh notifications")
                    .accessibilityHint("Reads the settings, pending and delivered notifications again")
            }
        }
    }

    extension NotificationSettings.Authorization {
        /// The issue glyph for how far the app may notify.
        fileprivate var severity: DebugDrawerIssueGlyph.Severity {
            switch self {
            case .authorized: .ok
            case .provisional, .ephemeral: .warning
            case .denied: .error
            case .notDetermined, .unknown: .neutral
            }
        }
    }
#endif
