import DebugDrawer
import DebugDrawerAppStateResetPlugin
import Foundation
import Security
import SwiftUI

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The example's Reset App State: the plugin installed with a cleanup of the example's own, and
/// state of every kind to clear, written on request.
enum ExampleAppStateReset {
    /// Launched with this argument, the app writes state of every kind before it starts, so a
    /// reset has something to clear and a fresh start can be told apart.
    static let launchArgument = "-SeedResettableState"
    /// Set once the example's onboarding was seen; a fresh install has it unset.
    static let onboardedKey = "exampleHasSeenOnboarding"
    /// The keychain item's service.
    static let keychainService = "com.debugdrawer.example.session"

    /// What the example's own cleanup clears: a session it keeps in memory only.
    @MainActor static var session: String?

    /// Writes the state when launched with ``launchArgument``, then installs the plugin. It
    /// compiles in release too, where the plugin does nothing.
    @MainActor
    static func install() {
        if ProcessInfo.processInfo.arguments.contains(launchArgument) {
            seed()
        }
        AppStateReset.install(cleanup: AppStateReset.Cleanup("Forget the example's in-memory session") {
            session = nil
        })
    }

    /// Writes UserDefaults keys, a keychain item, files in Documents, Application Support and tmp,
    /// a cached file, a URL cache entry and a persistent cookie.
    @MainActor
    static func seed() {
        session = "seeded"
        UserDefaults.standard.set(true, forKey: onboardedKey)
        UserDefaults.standard.set(5, forKey: ExampleTweaks.counterKey)

        let item: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: "seeded-user",
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemDelete(item as CFDictionary)
        var added = item
        added[kSecValueData as String] = Data("seeded-token".utf8)
        SecItemAdd(added as CFDictionary, nil)

        let files: [URL: String] = [
            URL.documentsDirectory.appending(path: "Seeded/notes.txt"): "Notes a fresh install doesn't have.",
            URL.applicationSupportDirectory.appending(path: "seeded.json"): #"{"seeded": true}"#,
            URL.temporaryDirectory.appending(path: "seeded.tmp"): "scratch",
            URL.cachesDirectory.appending(path: "Seeded/thumbnail.dat"): String(repeating: "x", count: 4096)
        ]
        for (url, contents) in files {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(contents.utf8).write(to: url)
        }

        if let url = URL(string: "https://example.com/seeded"),
           let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: ["Cache-Control": "max-age=86400"]) {
            let cached = CachedURLResponse(response: response, data: Data(repeating: 7, count: 64 * 1024))
            URLCache.shared.storeCachedResponse(cached, for: URLRequest(url: url))
        }

        let cookie = HTTPCookie(properties: [
            .domain: "example.com", .path: "/", .name: "session", .value: "seeded",
            .expires: Date.now.addingTimeInterval(86400)
        ])
        if let cookie {
            HTTPCookieStorage.shared.setCookie(cookie)
        }
    }
}

/// Whether the example's onboarding was seen and its session, which Reset App State clears.
struct ExampleResettableState: View {
    @AppStorage(ExampleAppStateReset.onboardedKey) private var hasSeenOnboarding = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(hasSeenOnboarding ? "Onboarding: seen" : "Onboarding: not seen (fresh install)")
            #if DEBUG
                Button("Seed State to Reset") { ExampleAppStateReset.seed() }
            #endif
        }
        .accessibilityElement(children: .contain)
    }
}
