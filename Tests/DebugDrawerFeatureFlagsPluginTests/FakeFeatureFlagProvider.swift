#if DEBUG
    import DebugDrawerFeatureFlagsPlugin

    /// A flag service held in memory, standing in for a vendor SDK: it serves `flags`, applies
    /// overrides to what `currentValue(forKey:)` reads, and records every override call.
    final class FakeFeatureFlagProvider: FeatureFlagProvider {
        enum Call: Equatable {
            case set(String, FeatureFlagValue)
            case clear(String)
        }

        var flagList: [FeatureFlag]
        var applied: [String: FeatureFlagValue] = [:]
        var calls: [Call] = []

        init(_ flags: [FeatureFlag] = []) {
            flagList = flags
        }

        func flags() -> [FeatureFlag] {
            flagList
        }

        func currentValue(forKey key: String) -> FeatureFlagValue? {
            applied[key] ?? flagList.first { $0.key == key }?.liveValue
        }

        func setOverride(_ value: FeatureFlagValue, forKey key: String) {
            calls.append(.set(key, value))
            applied[key] = value
        }

        func clearOverride(forKey key: String) {
            calls.append(.clear(key))
            applied[key] = nil
        }
    }

    /// Override storage held in memory, standing in for `UserDefaults`; two stores over one instance
    /// share it, as two launches share the defaults.
    final class FakeFeatureFlagOverrideStorage: FeatureFlagOverrideStorage {
        var values: [String: FeatureFlagValue]

        init(_ values: [String: FeatureFlagValue] = [:]) {
            self.values = values
        }

        func overrides() -> [String: FeatureFlagValue] {
            values
        }

        func setOverride(_ value: FeatureFlagValue?, forKey key: String) {
            values[key] = value
        }
    }
#endif
