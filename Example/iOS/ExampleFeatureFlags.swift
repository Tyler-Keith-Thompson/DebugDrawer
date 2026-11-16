import DebugDrawer
import DebugDrawerFeatureFlagsPlugin
import SwiftUI

// The macOS example has its own copy of this file: each app is its own module, and the examples
// share no code.

/// A sample adapter, standing in for a flag service's SDK: the flags' live values held in memory,
/// with the overrides the drawer applies winning over them. The drawer keeps the overrides in the
/// defaults and applies them again at launch, so they persist although this adapter forgets them.
/// Observable, so the example's views follow an override as the drawer sets it.
final class InMemoryFeatureFlagProvider: FeatureFlagProvider, ObservableObject {
    let live: [FeatureFlag]
    @Published private var overrides: [String: FeatureFlagValue] = [:]

    init(_ live: [FeatureFlag]) {
        self.live = live
    }

    func flags() -> [FeatureFlag] {
        live
    }

    func currentValue(forKey key: String) -> FeatureFlagValue? {
        overrides[key] ?? live.first { $0.key == key }?.liveValue
    }

    func setOverride(_ value: FeatureFlagValue, forKey key: String) {
        overrides[key] = value
    }

    func clearOverride(forKey key: String) {
        overrides[key] = nil
    }
}

/// The example's feature flags, as its flag service would serve them.
enum ExampleFeatureFlags {
    @MainActor static let provider = InMemoryFeatureFlagProvider([
        FeatureFlag(key: "new-checkout", liveValue: .bool(false), title: "New checkout", detail: "The one-page payment sheet"),
        FeatureFlag(key: "checkout-button-color", liveValue: .string("blue"), title: "Checkout button color"),
        FeatureFlag(key: "free-shipping-threshold", liveValue: .number(50), title: "Free shipping over ($)"),
        FeatureFlag(key: "promo-banner", liveValue: .bool(true), title: "Promo banner")
    ])

    #if DEBUG
        /// Adds the Feature Flags plugin over the sample adapter.
        @MainActor
        static func install() {
            DebugDrawer.shared.installFeatureFlags(provider: provider)
        }
    #endif
}

/// What the example's checkout would look like, read from the flags, following overrides as the
/// drawer sets them.
struct ExampleFeatureFlagsSummary: View {
    @ObservedObject private var flags = ExampleFeatureFlags.provider

    var body: some View {
        let isNewCheckout = flags.currentValue(forKey: "new-checkout") == .bool(true)
        let color = flags.currentValue(forKey: "checkout-button-color")?.description ?? "blue"
        let threshold = flags.currentValue(forKey: "free-shipping-threshold")?.description ?? "50"
        Text("Checkout: \(isNewCheckout ? "new" : "legacy"), \(color) button, free shipping over $\(threshold)")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
