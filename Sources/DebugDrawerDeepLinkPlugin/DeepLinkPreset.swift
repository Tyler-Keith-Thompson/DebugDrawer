import Foundation

/// A named URL the Deep Link Tester lists under Presets, which a tap puts in its field.
///
/// Pass presets to ``DebugDrawer/DebugDrawer/installDeepLink(presets:continueUserActivity:openURL:)``.
/// By default it lists ``bundleURLSchemes``, one for each URL scheme the app declares:
///
/// ```swift
/// DebugDrawer.shared.installDeepLink(presets: DeepLinkPreset.bundleURLSchemes + [
///     DeepLinkPreset("Order 42", url: URL(string: "myapp://orders/42")!)
/// ])
/// ```
///
/// The type exists in every build, so the call compiles unchanged in release, where nothing
/// lists it.
public struct DeepLinkPreset: Hashable, Sendable {
    /// The name shown beside the URL.
    public var label: String
    /// The URL a tap puts in the field.
    public var url: URL

    /// A preset named `label` that puts `url` in the field.
    ///
    /// - Parameters:
    ///   - label: The name shown beside the URL.
    ///   - url: The URL a tap puts in the field.
    public init(_ label: String, url: URL) {
        self.label = label
        self.url = url
    }

    /// One preset for each URL scheme the app's Info.plist declares under `CFBundleURLTypes`,
    /// in the order declared: the scheme's root URL (`myapp://`), named by its URL type's
    /// `CFBundleURLName`, or by the scheme when the type has no name. Empty when the app declares
    /// no URL scheme.
    public static var bundleURLSchemes: [DeepLinkPreset] {
        bundleURLSchemes(in: Bundle.main.infoDictionary ?? [:])
    }

    /// One preset for each scheme `infoDictionary` declares under `CFBundleURLTypes`.
    static func bundleURLSchemes(in infoDictionary: [String: Any]) -> [DeepLinkPreset] {
        let urlTypes = infoDictionary["CFBundleURLTypes"] as? [[String: Any]] ?? []
        return urlTypes.flatMap { urlType in
            let schemes = urlType["CFBundleURLSchemes"] as? [String] ?? []
            let name = urlType["CFBundleURLName"] as? String
            return schemes.compactMap { scheme in
                URL(string: "\(scheme)://").map { DeepLinkPreset(name ?? scheme, url: $0) }
            }
        }
    }
}
