#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import Foundation

    /// Signing the test chooses: the profile's bytes and the app's own entitlements, each read
    /// counted.
    final class FakeSigningInformation: SigningInformation {
        let profile: Data?
        let ownEntitlements: Entitlements?
        private(set) var reads = 0

        init(profile: Data? = nil, entitlements: Entitlements? = nil) {
            self.profile = profile
            ownEntitlements = entitlements
        }

        func embeddedProfile() -> Data? {
            reads += 1
            return profile
        }

        func entitlements() -> Entitlements? {
            ownEntitlements
        }
    }
#endif
