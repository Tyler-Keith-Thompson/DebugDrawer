#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Whether the app may notify, each presentation setting, Request while the user hasn't
    /// decided, and Refresh.
    struct AuthorizationSection: View {
        let settings: NotificationSettings
        let request: AuthorizationRequestState
        let onRequest: () -> Void
        let onRefresh: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                NotificationsSectionHeading(title: "Authorization")
                DebugDrawerKeyValueRow("Status", value: settings.authorization.title, labelWidth: 120)
                ForEach(settings.items, id: \.name) { item in
                    DebugDrawerKeyValueRow(item.name, value: item.value, labelWidth: 120)
                }
                if case let .failed(message) = request {
                    Text("Asking failed: \(message)")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                buttons
            }
        }

        /// Request, while it can be asked for, and Refresh: side by side, or one above the other at
        /// accessibility text sizes.
        private var buttons: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout())
            return layout {
                if settings.authorization == .notDetermined {
                    if request == .requesting {
                        HStack(spacing: 4) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Asking…")
                                .font(.caption)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Asking for notification access")
                    } else {
                        Button("Request", action: onRequest)
                            .accessibilityLabel("Request notification access")
                            .accessibilityHint("Shows the system's prompt")
                    }
                }
                Button("Refresh", action: onRefresh)
                    .accessibilityLabel("Refresh notifications")
                    .accessibilityHint("Reads the settings, pending and delivered notifications again")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
#endif
