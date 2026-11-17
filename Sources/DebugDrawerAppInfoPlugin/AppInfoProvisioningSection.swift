#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The Provisioning section: the profile's name, team, dates and devices, a warning when it
    /// has expired, or a None row when the app has no profile.
    struct AppInfoProvisioningSection: View {
        let profile: AppSigning.Profile
        let isExpired: Bool

        var body: some View {
            DebugDrawerSection("Provisioning") {
                switch profile {
                case .none:
                    DebugDrawerKeyValueRow("Profile", value: "None")
                case .unreadable:
                    DebugDrawerIssueRow("Profile", status: "Unreadable", severity: .warning)
                case let .embedded(profile):
                    if isExpired {
                        DebugDrawerIssueRow("Profile", status: "Expired", severity: .warning)
                    }
                    DebugDrawerKeyValueRow("Name", value: profile.name)
                    DebugDrawerKeyValueRow("Team", value: profile.teamName)
                    DebugDrawerKeyValueRow("Team ID", value: profile.teamIdentifier)
                    DebugDrawerKeyValueRow("Created", value: ProvisioningProfile.format(profile.creationDate))
                    DebugDrawerKeyValueRow("Expires", value: ProvisioningProfile.format(profile.expirationDate))
                    DebugDrawerKeyValueRow("Devices", value: profile.devices.text)
                }
            }
        }
    }
#endif
