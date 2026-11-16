#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The APNs device token as hexadecimal, masked under the drawer's rules until revealed, with
    /// Copy Token; or why there is none.
    struct DeviceTokenSection: View {
        let registration: RemoteRegistration
        let redaction: DebugDrawerRedaction

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                NotificationsSectionHeading(title: "APNs Device Token")
                switch registration {
                case .notRegistered:
                    Text("""
                    None reported. The app calls registerForRemoteNotifications() and passes the token to \
                    PushNotifications.didRegisterForRemoteNotifications(withDeviceToken:).
                    """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                case let .registered(deviceToken):
                    let token = deviceToken.hexadecimal
                    RedactedText(token, redacted: redaction.redacting(token, forKey: RemoteRegistration.redactionKey))
                        .font(.system(.caption2, design: .monospaced))
                        .fixedSize(horizontal: false, vertical: true)
                    // The token itself, whatever the rules: a push tool needs it, and the mask
                    // would be no use on the clipboard. Pressing the button is the choice to copy it.
                    DebugDrawerCopyButton("Copy Token") { token }
                case let .failed(message):
                    Label {
                        Text("Registering failed: \(message)")
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .accessibilityHidden(true)
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }
        }
    }
#endif
