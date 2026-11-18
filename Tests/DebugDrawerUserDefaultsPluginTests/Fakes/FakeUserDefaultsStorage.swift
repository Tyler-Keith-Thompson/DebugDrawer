#if DEBUG
    import Combine
    @testable import DebugDrawerUserDefaultsPlugin
    import Foundation

    /// Suites in memory: each suite's persistent domain, and the other domains, which every suite
    /// shares. `announceChange()` calls every observer as a write would; `onRead` runs at each read
    /// of a persistent domain, so a test can await the read a change schedules.
    @MainActor
    final class FakeUserDefaultsStorage: UserDefaultsStorage {
        /// Each suite's persistent domain.
        var suites: [UserDefaultsSuite: [String: Any]]
        /// The argument, global and registration domains.
        var otherDomains: [DefaultsDomain: [String: Any]]
        private(set) var reads = 0
        var onRead: (() -> Void)?
        private var observers: [UUID: @Sendable () -> Void] = [:]

        init(suites: [UserDefaultsSuite: [String: Any]] = [:], otherDomains: [DefaultsDomain: [String: Any]] = [:]) {
            self.suites = suites
            self.otherDomains = otherDomains
        }

        /// How many observers are registered.
        var observerCount: Int {
            observers.count
        }

        func values(in suite: UserDefaultsSuite, domain: DefaultsDomain) -> [String: Any] {
            guard domain == .persistent else { return otherDomains[domain, default: [:]] }
            reads += 1
            onRead?()
            return suites[suite, default: [:]]
        }

        func set(_ value: Any, forKey key: String, in suite: UserDefaultsSuite) {
            suites[suite, default: [:]][key] = value
        }

        func removeValue(forKey key: String, in suite: UserDefaultsSuite) {
            suites[suite]?[key] = nil
        }

        func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyCancellable {
            let id = UUID()
            observers[id] = onChange
            return AnyCancellable { [weak self] in
                MainActor.assumeIsolated { _ = self?.observers.removeValue(forKey: id) }
            }
        }

        /// Calls each observer, as a write to any suite does.
        func announceChange() {
            for onChange in observers.values {
                onChange()
            }
        }
    }
#endif
