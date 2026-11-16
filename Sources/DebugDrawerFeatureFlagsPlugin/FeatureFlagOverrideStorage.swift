// Foundation only, and in every build: see FeatureFlagValue.swift.
import Foundation

/// Where the drawer keeps feature flag overrides between launches, by flag key.
///
/// The drawer reads and writes it on the main actor. The default,
/// ``UserDefaultsFeatureFlagOverrideStorage``, keeps them in the standard defaults; pass another to
/// `installFeatureFlags(provider:storage:)` to keep them elsewhere. The protocol exists in every
/// build so a conformance compiles unchanged in release, where nothing calls it.
public protocol FeatureFlagOverrideStorage {
    /// Every stored override, by flag key.
    func overrides() -> [String: FeatureFlagValue]

    /// Stores `value` as the override for `key`; `nil` removes it.
    func setOverride(_ value: FeatureFlagValue?, forKey key: String)
}

/// Feature flag overrides in `UserDefaults`: one JSON object of key to value, under one defaults
/// key, so they can't collide with the app's own keys.
public struct UserDefaultsFeatureFlagOverrideStorage: FeatureFlagOverrideStorage {
    /// The defaults key the default storage keeps the overrides under.
    public static let defaultKey = "com.debugdrawer.featureFlags.overrides"

    /// The defaults the overrides live in.
    public let defaults: UserDefaults
    /// The defaults key they are kept under.
    public let key: String

    /// - Parameters:
    ///   - defaults: The defaults to keep the overrides in; the standard defaults unless given.
    ///   - key: The defaults key to keep them under.
    public init(defaults: UserDefaults = .standard, key: String = Self.defaultKey) {
        self.defaults = defaults
        self.key = key
    }

    /// Every stored override; none when nothing is stored or what is stored isn't an object of
    /// flag values.
    public func overrides() -> [String: FeatureFlagValue] {
        guard let data = defaults.data(forKey: key) else { return [:] }
        return (try? JSONDecoder().decode([String: FeatureFlagValue].self, from: data)) ?? [:]
    }

    public func setOverride(_ value: FeatureFlagValue?, forKey flagKey: String) {
        var overrides = overrides()
        overrides[flagKey] = value
        if overrides.isEmpty {
            defaults.removeObject(forKey: key)
        } else {
            // An object of strings to Booleans, finite numbers and strings always encodes;
            // a non-finite number is the one value that can't, and it is dropped with the write.
            if let data = try? JSONEncoder().encode(overrides) {
                defaults.set(data, forKey: key)
            }
        }
    }
}
