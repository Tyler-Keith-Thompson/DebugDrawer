import DebugDrawer
import DebugDrawerNotifications
import DebugDrawerSidecarKit
import SwiftUI

extension DebugDrawerSidecarPlugin {
    /// The host's APNs device token, push environment and notification settings
    /// (`DebugDrawerReceiverCapability.pushRegistration`), to aim a test push at the device.
    @MainActor static var pushRegistration: DebugDrawerSidecarPlugin {
        DebugDrawerSidecarPlugin(
            id: PushRegistrationMirror.pluginID, title: "Push Registration", icon: "app.badge",
            snapshot: PushRegistrationMirror.Snapshot.self, command: PushRegistrationMirror.Command.self
        ) { transport in
            PushRegistrationPlugin(transport: transport)
        }
    }
}

/// The host's device token to copy, the APNs server a test push goes to, and its notification
/// authorization and settings, with Refresh.
struct PushRegistrationPlugin: DebugDrawerPlugin {
    let transport: DebugDrawerPluginTransport<PushRegistrationMirror.Snapshot, PushRegistrationMirror.Command>
    let title = "Push Registration"
    let icon = "app.badge"

    var body: some View {
        PushRegistrationView(transport: transport)
    }
}

private struct PushRegistrationView: View {
    @ObservedObject var transport: DebugDrawerPluginTransport<PushRegistrationMirror.Snapshot, PushRegistrationMirror.Command>

    var body: some View {
        if let registration = transport.snapshot.registration {
            DebugDrawerSection("APNs Device Token") {
                switch registration {
                case .notRegistered:
                    DebugDrawerKeyValueRow("Token", value: "None reported yet")
                case let .registered(deviceToken):
                    DebugDrawerCodeBlock {
                        DebugDrawerCodeText(deviceToken)
                    }
                    DebugDrawerActionRow {
                        DebugDrawerCopyButton("Copy Token") { deviceToken }
                    }
                case let .failed(message):
                    DebugDrawerKeyValueRow("Registering failed", value: message)
                }
            }
            DebugDrawerSection("Environment") {
                DebugDrawerKeyValueRow("Server", value: transport.snapshot.environment.map(\.serverTitle) ?? "Not signed for push")
                DebugDrawerKeyValueRow("Source", value: transport.snapshot.environment.map(\.sourceTitle) ?? "None")
            }
            DebugDrawerSection("Notifications") {
                if let settings = transport.snapshot.settings {
                    DebugDrawerKeyValueRow("Authorization", value: settings.authorization.title)
                    ForEach(settings.items, id: \.name) { item in
                        DebugDrawerKeyValueRow(item.name, value: item.value)
                    }
                } else {
                    DebugDrawerKeyValueRow("Authorization", value: "Reading…")
                }
                DebugDrawerActionRow {
                    Button("Refresh") { transport.send(.refresh) }
                        .accessibilityHint("Reads the app's notification settings again")
                }
            }
        } else {
            DebugDrawerEmptyState("No Session", systemImage: "app.badge") {
                Text(
                    transport.snapshot.sessionID == nil
                        ? "The app shows its device token only during a session."
                        : "This session's grant doesn't list push registration."
                )
            }
        }
    }
}

extension PushEnvironment {
    /// The APNs server, with its host name.
    fileprivate var serverTitle: String {
        switch server {
        case .production: "Production (api.push.apple.com)"
        case .sandbox: "Sandbox (api.sandbox.push.apple.com)"
        }
    }

    /// Where the app's environment came from.
    fileprivate var sourceTitle: String {
        switch source {
        case .host: "Stated by the app"
        case .entitlement: "Code signature entitlement"
        case .provisioningProfile: "Embedded provisioning profile"
        case .appStoreDistribution: "App Store or TestFlight build"
        }
    }
}
