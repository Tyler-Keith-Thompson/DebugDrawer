@testable import DebugDrawerDeepLinkPlugin
import Foundation
import Testing

@Suite
struct DeepLinkPresetTests {
    @Test("Each scheme the Info.plist declares becomes a preset of its root URL, named by its URL type, in the order declared")
    func presetsFromInfoPlist() throws {
        let infoDictionary: [String: Any] = [
            "CFBundleURLTypes": [
                ["CFBundleURLName": "Orders", "CFBundleURLSchemes": ["myapp", "myapp-beta"]],
                ["CFBundleURLSchemes": ["auth-callback"]]
            ]
        ]
        let expected = try [
            DeepLinkPreset("Orders", url: #require(URL(string: "myapp://"))),
            DeepLinkPreset("Orders", url: #require(URL(string: "myapp-beta://"))),
            DeepLinkPreset("auth-callback", url: #require(URL(string: "auth-callback://")))
        ]

        let actual = DeepLinkPreset.bundleURLSchemes(in: infoDictionary)

        #expect(actual == expected)
    }

    @Test("An Info.plist with no URL types, or a URL type with no schemes, gives no presets")
    func noSchemes() {
        let noTypes: [String: Any] = ["CFBundleIdentifier": "com.example.app"]
        let noSchemes: [String: Any] = ["CFBundleURLTypes": [["CFBundleURLName": "Empty"]]]

        let actualWithoutTypes = DeepLinkPreset.bundleURLSchemes(in: noTypes)
        let actualWithoutSchemes = DeepLinkPreset.bundleURLSchemes(in: noSchemes)

        #expect(actualWithoutTypes.isEmpty)
        #expect(actualWithoutSchemes.isEmpty)
    }

    @Test("The default presets are the main bundle's own schemes, and hold no private scheme such as App-prefs:")
    func defaultsHoldNoPrivateScheme() {
        let privateSchemes: Set<String> = ["app-prefs", "prefs", "app-settings"]
        let declared = Set(
            (Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? [])
                .flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] }
                .map { $0.lowercased() }
        )

        let actual = DeepLinkPreset.bundleURLSchemes

        let schemes = Set(actual.compactMap { $0.url.scheme?.lowercased() })
        #expect(schemes == declared)
        #expect(schemes.isDisjoint(with: privateSchemes))
    }
}
