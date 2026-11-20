import Combine
import DebugDrawerReceiver

/// The example's flag service: live values in memory, with local overrides winning, which a
/// sidecar sets through the feature flag overrides capability.
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
