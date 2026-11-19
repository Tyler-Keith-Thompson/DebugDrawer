#if DEBUG
    import Foundation

    /// How the app was signed, as App Info shows it: its provisioning profile and its entitlements.
    struct AppSigning: Codable, Equatable, Sendable {
        /// What the bundle holds of a provisioning profile.
        enum Profile: Codable, Equatable, Sendable {
            /// No profile: a simulator, App Store or unprovisioned Mac build.
            case none
            /// A profile file that can't be read as one.
            case unreadable
            /// The profile the app was signed with.
            case embedded(ProvisioningProfile)
        }

        var profile: Profile
        /// The entitlements the app runs with; `nil` when none could be read.
        var entitlements: Entitlements?

        init(profile: Profile, entitlements: Entitlements?) {
            self.profile = profile
            self.entitlements = entitlements
        }

        /// The signing `source` reports: the app's own entitlements where it carries them, the
        /// profile's otherwise, as on a device.
        init(reading source: some SigningInformation) {
            let profile: Profile = source.embeddedProfile().map { data in
                (try? ProvisioningProfile(profileData: data)).map(Profile.embedded) ?? .unreadable
            } ?? .none
            self.init(profile: profile, entitlements: source.entitlements() ?? profile.provisioningProfile?.entitlements)
        }
    }

    extension AppSigning.Profile {
        var provisioningProfile: ProvisioningProfile? {
            if case let .embedded(profile) = self { profile } else { nil }
        }
    }
#endif
