import DebugDrawer
#if canImport(DebugDrawerNotifications)
    import DebugDrawerNotifications
#endif
import Foundation
import SwiftUI

// The sidecar's half of push registration (DD-115): the APNs device token the app hands its
// mirror (`PushRegistrationMirror`, in DebugDrawerNotifications), to copy into the tool that sends a
// test push, the APNs server that push goes to, and the app's notification authorization and
// settings, with Refresh. It ships in the kit, as the snapshot describes itself, so every sidecar
// would draw the same rows. The app serves the token only during a session (and, under a grant
// policy, only to one whose grant lists the mirror); the empty state says which.
// DebugDrawerNotifications doesn't build for watchOS, so the kit has no `pushRegistration` there
// (PLATFORM_CONDITIONAL_DEPENDENCIES in scripts/modules.py).

#if DEBUG && canImport(DebugDrawerNotifications)
    extension DebugDrawerSidecarPlugin {
        /// The app's APNs device token, push environment and notification settings
        /// (`DebugDrawerReceiverCapability.pushRegistration(_:)`), to aim a test push at the device,
        /// with Copy Token and Refresh.
        @MainActor public static var pushRegistration: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: PushRegistrationMirror.pluginID, title: "Push Registration", icon: "app.badge",
                snapshot: PushRegistrationMirror.Snapshot.self, command: PushRegistrationMirror.Command.self
            ) { transport in
                PushRegistrationSidecarPlugin(transport: transport)
            }
        }
    }

    /// The app's push registration, shown in the sidecar.
    struct PushRegistrationSidecarPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<PushRegistrationMirror.Snapshot, PushRegistrationMirror.Command>
        let title = "Push Registration"
        let icon = "app.badge"

        var body: some View {
            PushRegistrationTransportView(transport: transport)
        }
    }

    /// The registration over the capability's snapshot, sending what the view asks.
    struct PushRegistrationTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<PushRegistrationMirror.Snapshot, PushRegistrationMirror.Command>

        var body: some View {
            PushRegistrationView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// The token, the environment and the notification settings with Refresh; or why the app
    /// serves none. A function of the snapshot and the send action.
    struct PushRegistrationView: View {
        let snapshot: PushRegistrationMirror.Snapshot
        let send: (PushRegistrationMirror.Command) -> Void

        var body: some View {
            if let registration = snapshot.registration {
                DebugDrawerSection("APNs Device Token") {
                    switch registration {
                    case .notRegistered:
                        DebugDrawerKeyValueRow("Token", value: "None reported yet")
                    case let .registered(deviceToken):
                        DebugDrawerCodeBlock {
                            DebugDrawerCodeText(deviceToken)
                        }
                        .accessibilityLabel("Device token \(deviceToken)")
                        DebugDrawerActionRow {
                            DebugDrawerCopyButton("Copy Token") { deviceToken }
                        }
                    case let .failed(message):
                        DebugDrawerKeyValueRow("Registering failed", value: message)
                    }
                }
                DebugDrawerSection("Environment") {
                    DebugDrawerKeyValueRow("Server", value: snapshot.environment.map(\.serverTitle) ?? "Not signed for push")
                    DebugDrawerKeyValueRow("Source", value: snapshot.environment.map(\.sourceTitle) ?? "None")
                }
                DebugDrawerSection("Notifications") {
                    if let settings = snapshot.settings {
                        DebugDrawerKeyValueRow("Authorization", value: settings.authorization.title)
                        ForEach(settings.items, id: \.name) { item in
                            DebugDrawerKeyValueRow(item.name, value: item.value)
                        }
                    } else {
                        DebugDrawerKeyValueRow("Authorization", value: "Reading…")
                    }
                    DebugDrawerActionRow {
                        Button("Refresh") { send(.refresh) }
                            .debugDrawerButtonStyle(.secondary)
                            .accessibilityLabel("Refresh")
                            .accessibilityHint("Reads the app's notification settings again")
                    }
                }
            } else {
                DebugDrawerEmptyState("No Token", systemImage: "app.badge") {
                    Text(
                        snapshot.sessionID == nil
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
#elseif canImport(DebugDrawerNotifications)
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The app's APNs device token and notification settings; release builds show nothing.
        @MainActor public static var pushRegistration: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: PushRegistrationMirror.pluginID, title: "Push Registration", icon: "app.badge",
                snapshot: PushRegistrationMirror.Snapshot.self, command: PushRegistrationMirror.Command.self
            ) { _ in
                PushRegistrationSidecarPlugin()
            }
        }
    }

    /// Draws nothing.
    struct PushRegistrationSidecarPlugin: DebugDrawerPlugin {
        let title = "Push Registration"
        let icon = "app.badge"

        var body: some View {
            EmptyView()
        }
    }
#endif
