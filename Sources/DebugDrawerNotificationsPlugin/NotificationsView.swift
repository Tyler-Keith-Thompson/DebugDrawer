#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The device token, the authorization and settings, the payload editor, and the pending and
    /// delivered notifications, one section each.
    struct NotificationsView: View {
        let registration: RemoteRegistration
        let center: NotificationCenterState
        let authorizationRequest: AuthorizationRequestState
        let sendState: SendState
        @Binding var draft: String
        @Binding var delay: SendDelay
        let redaction: DebugDrawerRedaction
        let actions: NotificationsActions

        var body: some View {
            VStack(alignment: .leading, spacing: 14) {
                DeviceTokenSection(registration: registration, redaction: redaction)
                switch center {
                case .loading:
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Reading the notification center…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                case let .loaded(snapshot):
                    AuthorizationSection(
                        settings: snapshot.settings,
                        request: authorizationRequest,
                        onRequest: actions.requestAuthorization,
                        onRefresh: actions.refresh
                    )
                    PayloadComposer(
                        draft: $draft,
                        delay: $delay,
                        sendState: sendState,
                        authorization: snapshot.settings.authorization,
                        onSend: actions.send
                    )
                    NotificationListSection(
                        kind: .pending,
                        notifications: snapshot.pending,
                        redaction: redaction,
                        onRemove: actions.removePending,
                        onRemoveAll: actions.removeAllPending
                    )
                    NotificationListSection(
                        kind: .delivered,
                        notifications: snapshot.delivered,
                        redaction: redaction,
                        onRemove: actions.removeDelivered,
                        onRemoveAll: actions.removeAllDelivered
                    )
                }
            }
        }
    }
#endif
