#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The APNs device token as hexadecimal, masked under the drawer's rules until revealed, with
    /// Copy Token; or why there is none.
    struct DeviceTokenSection: View {
        let registration: RemoteRegistration
        let redaction: DebugDrawerRedaction

        var body: some View {
            DebugDrawerSection("APNs device token") {
                switch registration {
                case .notRegistered:
                    DebugDrawerIssueRow("No token", severity: .neutral) {
                        Text("""
                        None reported. The app calls registerForRemoteNotifications() and passes the token to \
                        PushNotifications.didRegisterForRemoteNotifications(withDeviceToken:).
                        """)
                    }
                case let .registered(deviceToken):
                    let token = deviceToken.hexadecimal
                    DebugDrawerCodeBlock {
                        RedactedText(token, redacted: redaction.redacting(token, forKey: RemoteRegistration.redactionKey))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // The token itself, whatever the rules: a push tool needs it, and the mask
                    // would be no use on the clipboard. Pressing the button is the choice to copy it.
                    DebugDrawerActionRow {
                        DebugDrawerCopyButton("Copy Token") { token }
                    }
                case let .failed(message):
                    DebugDrawerIssueRow("Registering failed: \(message)", severity: .error)
                }
            }
        }
    }
#endif
