#if DEBUG
    @testable import DebugDrawerAppStateResetPlugin
    @testable import DebugDrawerAppStateReset

    /// UserDefaults domains in memory: each domain's keys, and every removal asked for.
    @MainActor
    final class FakePreferenceStore: PreferenceStore {
        var domains: [String: Set<String>]
        private(set) var removed: [String: [String]] = [:]

        init(_ domains: [String: Set<String>] = [:]) {
            self.domains = domains
        }

        func keys(inDomain name: String) -> [String] {
            (domains[name] ?? []).sorted()
        }

        func remove(_ keys: [String], fromDomain name: String) {
            domains[name]?.subtract(keys)
            removed[name, default: []] += keys
        }
    }
#endif
