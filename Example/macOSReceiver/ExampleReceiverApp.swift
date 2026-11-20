import DebugDrawerAccessibility
import DebugDrawerLocalization
import DebugDrawerReceiver
import DebugDrawerTweaks
import SwiftUI

// A production app's view of DebugDrawer: it links the receiver and the capability modules and
// nothing else of the library, so its release build carries no drawer, no plugin and no
// interception (`just release-check` builds it optimized). It serves a sidecar app four
// capabilities, its feature flag overrides, its production-safe tweaks, a localization review of
// the strings it reads through `LocalizationReview` and accessibility overrides of its window's
// environment, within sessions of at most 15 minutes, through the app group's store, and draws
// its own indicator while a session is open. Without the app group (the example is signed ad hoc)
// the store lives in Caches, where only the app itself reaches it.

/// The example's flag service: live values in memory, with local overrides winning.
@MainActor
final class ProductionFlags: ObservableObject, DebugDrawerFeatureFlagAdapter {
    private let live: [String: DebugDrawerFeatureFlagValue] = [
        "new-checkout": .bool(false),
        "checkout-button-color": .string("blue")
    ]
    @Published private var overrides: [String: DebugDrawerFeatureFlagValue] = [:]

    func value(forKey key: String) -> DebugDrawerFeatureFlagValue? {
        overrides[key] ?? live[key]
    }

    func overridableFlags() -> [DebugDrawerFeatureFlag] {
        live.keys.sorted().compactMap { key in value(forKey: key).map { DebugDrawerFeatureFlag(key: key, value: $0) } }
    }

    func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
        overrides[key] = value
    }

    func clearOverride(forKey key: String) {
        overrides[key] = nil
    }
}

/// The example's tweaks: the greeting is production-safe, so a sidecar may change it in release;
/// the diagnostics toggle isn't, so it stays at its default there and a sidecar never sees it.
enum ProductionTweaks {
    static let greeting = Tweak.text("Greeting", key: "greeting", default: "Welcome").productionSafe()
    static let diagnostics = Tweak.toggle("Diagnostics", key: "diagnostics", default: false)
}

@main
struct ExampleReceiverApp: App {
    @StateObject private var flags: ProductionFlags
    @StateObject private var sessions: DebugDrawerSessions
    @State private var greeting = ProductionTweaks.greeting.value
    private let receiver: DebugDrawerReceiver

    init() {
        let flags = ProductionFlags()
        let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.debugdrawer.example")
            ?? URL.cachesDirectory
        let directory = container.appending(path: "DebugDrawerSidecar", directoryHint: .isDirectory)
        let receiver = DebugDrawerReceiver(directory: directory, sessions: sessions)
        receiver.enable(.featureFlagOverrides(flags))
        receiver.enable(.tweaks(ProductionTweaks.greeting, ProductionTweaks.diagnostics))
        receiver.enable(.localizationReview())
        receiver.enable(.accessibilityEnvironmentOverrides())
        do {
            try receiver.start()
        } catch {
            print("[Receiver] The store isn't reachable, so no sidecar can reach the app: \(error)")
        }
        _flags = StateObject(wrappedValue: flags)
        _sessions = StateObject(wrappedValue: sessions)
        self.receiver = receiver
    }

    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text(greeting)
                    .onReceive(ProductionTweaks.greeting.publisher) { greeting = $0 }
                Text("Checkout: \(flags.value(forKey: "new-checkout") == .bool(true) ? "new" : "legacy")")
                Text(LocalizationReview.shared.localizedString(forKey: "orders.title", value: "Orders"))
                if let session = sessions.snapshot.session {
                    HStack {
                        Text("Debug session until \(session.expires, style: .time)")
                        Button("End Session") { sessions.end() }
                    }
                    .accessibilityIdentifier("SidecarSessionIndicator")
                }
            }
            .padding()
            .localizationReview()
            .accessibilityEnvironmentOverrides()
        }
    }
}
