import Foundation
import Network

// What a device advertises over Bonjour and a viewer browses for: one service type, which the
// host app also lists under NSBonjourServices, and a TXT record naming the app, so a viewer can
// tell two apps on one device apart before it pairs. Pure values, so tests check what would be
// advertised without advertising anything on this Mac's network.

/// The Bonjour service a ``DebugDrawerNetworkServer`` advertises and a
/// ``DebugDrawerNetworkBrowser`` browses for.
public enum DebugDrawerBonjourService {
    /// The service type, `_debugdrawer._tcp`: list it under `NSBonjourServices` in the app's
    /// Info.plist.
    public static let type = "_debugdrawer._tcp"

    /// The handshake's version in the TXT record, so a viewer can leave out devices it can't
    /// pair with.
    static let protocolVersion = "1"

    /// The TXT record's keys.
    enum Key {
        static let version = "v"
        static let appName = "app"
        static let bundleIdentifier = "bundle"
        static let platform = "os"
    }

    /// The TXT record for an app: the handshake's version and, when known, the app's name, bundle
    /// identifier and platform.
    static func txtRecord(appName: String?, bundleIdentifier: String?, platform: String) -> [String: String] {
        var record = [Key.version: protocolVersion, Key.platform: platform]
        record[Key.appName] = appName
        record[Key.bundleIdentifier] = bundleIdentifier
        return record
    }

    /// The TXT record for this app, from its main bundle.
    static func currentTXTRecord() -> [String: String] {
        let info = Bundle.main.infoDictionary
        let name = (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
        return txtRecord(appName: name, bundleIdentifier: Bundle.main.bundleIdentifier, platform: currentPlatform)
    }

    /// The service a listener advertises: `name`, or the device's name when `nil`, of ``type``,
    /// with `txtRecord`.
    static func listenerService(name: String?, txtRecord: [String: String]) -> NWListener.Service {
        NWListener.Service(name: name, type: type, domain: nil, txtRecord: NWTXTRecord(txtRecord))
    }

    /// The platform this build runs on, as `os(...)` spells it.
    static var currentPlatform: String {
        #if os(macOS)
            "macOS"
        #elseif targetEnvironment(macCatalyst)
            "macCatalyst"
        #elseif os(iOS)
            "iOS"
        #elseif os(visionOS)
            "visionOS"
        #elseif os(tvOS)
            "tvOS"
        #else
            "watchOS"
        #endif
    }
}
