import Foundation
#if os(macOS)
    import Security
#endif

// Which APNs server a device token belongs to is the app's signature's business: the
// `aps-environment` entitlement (`com.apple.developer.aps-environment` on the Mac) says
// `development` (the sandbox) or `production`. The library reads it where the platform lets it:
// on the Mac from the running code's own signature (SecTask, public there), elsewhere from the
// provisioning profile embedded in the bundle, whose plist sits in plain text inside the CMS
// envelope. An iOS build from the App Store or TestFlight carries no profile and is always
// production, so no profile on a device reads as that. The host can say otherwise.
//
// Rejected: asking the host always (most hosts would hard-code it and be wrong in one of their
// builds), reading the entitlement with SecTask on iOS (not public API there), decoding the CMS
// envelope with Security's CMSDecoder (macOS only; the plist inside is what is wanted, and the
// signature was checked by the system at install), and an `#if DEBUG` guess (a debug build can be
// signed for production and a release build for the sandbox).

/// The APNs environment a device token belongs to, and how the library knows it: a test push
/// must go to the server the token was issued by.
public struct PushEnvironment: Codable, Equatable, Sendable {
    /// The APNs server a token belongs to.
    public enum Server: String, Codable, Sendable {
        /// `api.push.apple.com`: App Store, TestFlight and Ad Hoc builds, and any signed with a
        /// production `aps-environment`.
        case production
        /// `api.sandbox.push.apple.com`: development-signed builds, whose `aps-environment` is
        /// `development`.
        case sandbox
    }

    /// Where the environment came from.
    public enum Source: String, Codable, Sendable {
        /// The host said so.
        case host
        /// The running app's own code signature's entitlement (the Mac).
        case entitlement
        /// The provisioning profile embedded in the app.
        case provisioningProfile
        /// An iOS app on a device with no embedded profile: App Store and TestFlight builds, which
        /// always use production.
        case appStoreDistribution
    }

    /// The server a test push must go to.
    public let server: Server
    /// How the library knows it.
    public let source: Source

    /// An environment.
    ///
    /// - Parameters:
    ///   - server: The APNs server.
    ///   - source: Where it came from; ``Source/host`` for one the host states.
    public init(server: Server, source: Source) {
        self.server = server
        self.source = source
    }

    /// The environment the running app is signed for, or `nil` when it carries no
    /// `aps-environment` entitlement (it can't receive pushes) or the platform gives no way to read
    /// it, such as a simulator build with no embedded profile.
    ///
    /// On the Mac it reads `com.apple.developer.aps-environment` from the process's own code
    /// signature; elsewhere `aps-environment` from the bundle's embedded provisioning profile,
    /// and, on an iOS device with none, takes the App Store's production environment.
    ///
    /// - Parameter bundle: The app's bundle.
    /// - Returns: The environment, or `nil`.
    public static func detected(in bundle: Bundle = .main) -> PushEnvironment? {
        #if os(macOS)
            return signatureEntitlement().flatMap { Server(entitlementValue: $0) }.map { PushEnvironment(server: $0, source: .entitlement) }
        #else
            if let profile = embeddedProfile(in: bundle) {
                return provisioningProfileServer(profile).map { PushEnvironment(server: $0, source: .provisioningProfile) }
            }
            #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
                // A simulator build carries no profile, and a Catalyst one without a profile is
                // signed for development or not at all: neither says anything.
                return nil
            #else
                return PushEnvironment(server: .production, source: .appStoreDistribution)
            #endif
        #endif
    }

    /// The server the `aps-environment` entitlement in the provisioning profile `profile` names,
    /// or `nil` when the profile can't be read or holds no such entitlement.
    ///
    /// A profile is a CMS-signed property list; this reads the property list inside it, from its
    /// XML declaration to its closing tag, without checking the signature, which the system checked
    /// as it installed the app.
    package static func provisioningProfileServer(_ profile: Data) -> Server? {
        guard let start = profile.range(of: Data("<?xml".utf8)),
              let end = profile.range(of: Data("</plist>".utf8), in: start.upperBound ..< profile.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                  from: profile[start.lowerBound ..< end.upperBound], format: nil
              ) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let value = (entitlements["aps-environment"] ?? entitlements["com.apple.developer.aps-environment"]) as? String
        else { return nil }
        return Server(entitlementValue: value)
    }

    #if os(macOS)
        /// The running process's `com.apple.developer.aps-environment` entitlement, if its
        /// signature holds one.
        private static func signatureEntitlement() -> String? {
            guard let task = SecTaskCreateFromSelf(nil) else { return nil }
            return SecTaskCopyValueForEntitlement(task, "com.apple.developer.aps-environment" as CFString, nil) as? String
        }
    #else
        /// The profile embedded in `bundle`: `embedded.mobileprovision` in an iOS app,
        /// `Contents/embedded.provisionprofile` in a Mac Catalyst one.
        private static func embeddedProfile(in bundle: Bundle) -> Data? {
            #if targetEnvironment(macCatalyst)
                let url = bundle.bundleURL.appending(path: "Contents/embedded.provisionprofile", directoryHint: .notDirectory)
            #else
                guard let url = bundle.url(forResource: "embedded", withExtension: "mobileprovision") else { return nil }
            #endif
            return try? Data(contentsOf: url)
        }
    #endif
}

extension PushEnvironment.Server {
    /// The server an `aps-environment` value names: `development` is the sandbox, `production`
    /// production; anything else, `nil`.
    package init?(entitlementValue: String) {
        switch entitlementValue {
        case "development": self = .sandbox
        case "production": self = .production
        default: return nil
        }
    }
}
