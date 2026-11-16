#if DEBUG
    import DebugDrawerTweaksPlugin

    /// Storage held in memory, standing in for `UserDefaults`; two stores over one instance share
    /// it, as two launches share the defaults.
    final class FakeTweakStorage: TweakStorage {
        var values: [String: TweakStoredValue]

        init(_ values: [String: TweakStoredValue] = [:]) {
            self.values = values
        }

        func value(forKey key: String) -> TweakStoredValue? {
            values[key]
        }

        func setValue(_ value: TweakStoredValue?, forKey key: String) {
            values[key] = value
        }
    }

    enum Server: String, CaseIterable, Sendable {
        case production, staging, local
    }

    enum RetryPolicy: Int, CaseIterable, Sendable {
        case never = 0, few = 3, many = 10
    }
#endif
