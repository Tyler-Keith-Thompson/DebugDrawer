import DebugDrawerUserDefaultsPlugin
import Foundation
import SwiftUI

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// The example's UserDefaults plugin: the standard defaults and an app group's suite, with keys
/// of every type to edit, and a button that writes a key as the app would.
enum ExampleUserDefaults {
    /// The app group whose suite the plugin offers beside Standard. The example declares no app
    /// group entitlement, so the suite is the app's own file of that name, which reads and writes
    /// the same.
    static let appGroup = "group.com.debugdrawer.example"
    /// The key Write Key sets: the time it was pressed.
    static let lastWriteKey = "exampleLastWrite"

    /// Seeds the group's suite with a value of each type, nested ones too, then installs the
    /// plugin. It compiles in release too, where the plugin does nothing.
    @MainActor
    static func install() {
        if let group = UserDefaults(suiteName: appGroup), group.object(forKey: "settings") == nil {
            group.set("ada", forKey: "username")
            group.set(3, forKey: "launchCount")
            group.set(Data([0xDE, 0xAD, 0xBE, 0xEF]), forKey: "token")
            group.set(["recent", "favorites"], forKey: "tabs")
            group.set(["theme": ["accent": "orange", "contrast": 1.5], "sync": true], forKey: "settings")
        }
        UserDefaultsBrowser.install(suites: [appGroup])
    }

    /// Writes the time to the standard defaults and the group's suite, as the app's own code
    /// would: the plugin's list shows it without a reload.
    static func writeKey() {
        let now = Date.now
        UserDefaults.standard.set(now, forKey: lastWriteKey)
        UserDefaults(suiteName: appGroup)?.set(now, forKey: lastWriteKey)
    }
}

/// Writes a key from the app, outside the plugin.
struct ExampleUserDefaultsWriter: View {
    var body: some View {
        Button("Write UserDefaults Key") { ExampleUserDefaults.writeKey() }
            .accessibilityHint("Sets \(ExampleUserDefaults.lastWriteKey) to now in both suites")
    }
}
