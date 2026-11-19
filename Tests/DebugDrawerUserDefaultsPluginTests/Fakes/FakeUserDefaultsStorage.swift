#if DEBUG
    import Combine
    @testable import DebugDrawerUserDefaultsPlugin
    import Foundation

    /// Suites in memory: each suite's persistent domain, and the other domains, which every suite
    /// shares. `writes` records each set and remove in the order made; `announceChange()` calls
    /// every observer as a write would; `onRead` runs at each read of a persistent domain, so a
    /// test can await the read a change schedules.
    @MainActor
    final class FakeUserDefaultsStorage: UserDefaultsStorage {
        /// A set or a remove, as the model made it.
        enum Write: Equatable {
            case set(String, PropertyListValue, UserDefaultsSuite)
            case remove(String, UserDefaultsSuite)
        }

        /// Each suite's persistent domain.
        var suites: [UserDefaultsSuite: [String: PropertyListValue]]
        /// The argument, global and registration domains.
        var otherDomains: [DefaultsDomain: [String: PropertyListValue]]
        private(set) var reads = 0
        private(set) var writes: [Write] = []
        var onRead: (() -> Void)?
        private var observers: [UUID: @Sendable () -> Void] = [:]

        init(
            suites: [UserDefaultsSuite: [String: PropertyListValue]] = [:],
            otherDomains: [DefaultsDomain: [String: PropertyListValue]] = [:]
        ) {
            self.suites = suites
            self.otherDomains = otherDomains
        }

        /// How many observers are registered.
        var observerCount: Int {
            observers.count
        }

        func values(in suite: UserDefaultsSuite, domain: DefaultsDomain) -> [String: PropertyListValue] {
            guard domain == .persistent else { return otherDomains[domain, default: [:]] }
            reads += 1
            onRead?()
            return suites[suite, default: [:]]
        }

        func set(_ value: PropertyListValue, forKey key: String, in suite: UserDefaultsSuite) {
            writes.append(.set(key, value, suite))
            suites[suite, default: [:]][key] = value
        }

        func removeValue(forKey key: String, in suite: UserDefaultsSuite) {
            writes.append(.remove(key, suite))
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
