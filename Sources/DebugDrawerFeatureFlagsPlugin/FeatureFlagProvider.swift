// Foundation only, and in every build: see FeatureFlagValue.swift.
import Foundation

/// The adapter between the drawer and the app's flag service (LaunchDarkly, Firebase Remote
/// Config, Statsig or the app's own): it lists the flags, says what the app reads for each, and
/// applies and removes local overrides.
///
/// The host writes one over its flag SDK, so the plugin depends on no vendor. Its override methods
/// only change what the app reads; the plugin keeps the overrides themselves in a
/// ``FeatureFlagOverrideStorage`` and applies each stored one again when it is installed, so an
/// adapter can hold its overrides in memory and they still persist across launches.
///
/// The drawer calls it on the main actor. The methods are synchronous because flag SDKs answer
/// from a local cache, and the overrides must be in place before the app's first read after
/// installing; an adapter over an asynchronous source answers from what it last fetched. The
/// protocol exists in every build so a conformance compiles unchanged in release, where nothing
/// calls it.
public protocol FeatureFlagProvider {
    /// Every flag the service knows, each with its live value, in the order to list them.
    func flags() -> [FeatureFlag]

    /// The value the app reads for `key` now: its override if one is applied, otherwise its live
    /// value; `nil` for a key the service doesn't know.
    func currentValue(forKey key: String) -> FeatureFlagValue?

    /// Makes the app read `value` for `key` until the override is cleared.
    func setOverride(_ value: FeatureFlagValue, forKey key: String)

    /// Makes the app read the live value for `key` again. Clearing a key with no override does
    /// nothing.
    func clearOverride(forKey key: String)
}
