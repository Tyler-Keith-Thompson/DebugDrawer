import DebugDrawer
import DebugDrawerTweaksPlugin
import os
import SwiftUI

// The iOS example declares the same tweaks in its own copy of this file: each app is its own
// module, and the examples share no code.

/// The servers the example could talk to.
enum ExampleServer: String, CaseIterable {
    case production, staging, local
}

/// The example's own debug settings. They exist in every build; in release each reads its default.
enum ExampleTweaks {
    private static let installLogger = Logger(subsystem: "ExampleApp", category: "ExampleTweaks")

    /// The defaults key the example's counter is kept under, which Reset counter removes.
    static let counterKey = "exampleCounter"
    static let counterStep = Tweak.stepper("Counter step", key: "counterStep", default: 1, in: 1 ... 10)
    static let showBanner = Tweak.toggle("Show banner", key: "showBanner", default: false)
    static let bannerText = Tweak.text("Banner text", key: "bannerText", default: "Hello from Tweaks")
    static let server = Tweak.picker("Server", key: "server", default: ExampleServer.production).productionSafe()

    /// Adds the Tweaks plugin.
    @MainActor
    static func install() {
        do {
            try installThrowing()
        } catch {
            installLogger.error("The Tweaks plugin refused its configuration: \(String(describing: error), privacy: .public)")
        }
    }

    /// What ``install()`` does, throwing what the plugin refuses.
    @MainActor
    private static func installThrowing() throws {
        try DebugDrawer.shared.installTweaks {
            TweakSection("Counter") {
                counterStep
                TweakAction("Reset counter") {
                    UserDefaults.standard.removeObject(forKey: counterKey)
                }
            }
            TweakSection("Banner") {
                showBanner
                bannerText
            }
            TweakSection("Server") {
                server
            }
        }
    }
}

/// A banner the Show banner tweak turns on, reading its text and the server from the tweaks, and
/// following them as they change.
struct ExampleTweaksBanner: View {
    @State private var isShown = ExampleTweaks.showBanner.value
    @State private var text = ExampleTweaks.bannerText.value
    @State private var server = ExampleTweaks.server.value

    var body: some View {
        Group {
            if isShown {
                Text("\(text) (\(server.rawValue))")
                    .padding(8)
                    .background(.yellow.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .onReceive(ExampleTweaks.showBanner.publisher) { isShown = $0 }
        .onReceive(ExampleTweaks.bannerText.publisher) { text = $0 }
        .onReceive(ExampleTweaks.server.publisher) { server = $0 }
    }
}
