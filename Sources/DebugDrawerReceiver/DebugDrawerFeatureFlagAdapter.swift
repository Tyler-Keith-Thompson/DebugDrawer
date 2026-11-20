import Foundation

/// The host's adapter between the receiver's feature flag overrides and its flag service
/// (LaunchDarkly, Firebase Remote Config, Statsig or its own).
///
/// It decides what a sidecar may touch: listing a flag in ``overridableFlags()`` marks it as one an
/// employee may override on their own device, so list only the flags a tester may see and
/// override, never one whose value is a secret. An override changes only what the app reads
/// through the adapter: a flag the server enforces stays enforced. The receiver calls it on the
/// main actor, only with a key the adapter listed and a value of the kind that flag already has,
/// and clears only keys it overrode.
///
/// ```swift
/// @MainActor
/// final class FlagAdapter: DebugDrawerFeatureFlagAdapter {
///     func overridableFlags() -> [DebugDrawerFeatureFlag] {
///         [DebugDrawerFeatureFlag(key: "new-checkout", value: .bool(FlagService.shared.bool("new-checkout")))]
///     }
///
///     func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String) {
///         FlagService.shared.setLocalOverride(value, forKey: key)
///     }
///
///     func clearOverride(forKey key: String) {
///         FlagService.shared.removeLocalOverride(forKey: key)
///     }
/// }
/// ```
@MainActor
public protocol DebugDrawerFeatureFlagAdapter {
    /// The flags a sidecar may see and override, each with the value the app reads for it now, in
    /// the order to list them.
    func overridableFlags() -> [DebugDrawerFeatureFlag]

    /// Makes the app read `value` for `key` until the override is cleared.
    ///
    /// - Parameters:
    ///   - value: The value, of the kind the flag already has.
    ///   - key: A key ``overridableFlags()`` listed.
    func setOverride(_ value: DebugDrawerFeatureFlagValue, forKey key: String)

    /// Makes the app read the flag service's value for `key` again.
    ///
    /// - Parameter key: A key the receiver overrode.
    func clearOverride(forKey key: String)
}
