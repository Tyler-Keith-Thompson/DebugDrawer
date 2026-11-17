#if DEBUG
    import Combine
    @testable import DebugDrawerUserDefaultsPlugin
    import Foundation

    /// Suites in memory. `announceChange()` calls every observer as a write would; `onRead` runs
    /// at each read, so a test can await the read a change schedules.
    @MainActor
    final class FakeUserDefaultsStorage: UserDefaultsStorage {
        var suites: [UserDefaultsSuite: [String: Any]]
        private(set) var reads = 0
        var onRead: (() -> Void)?
        private var observers: [UUID: @Sendable () -> Void] = [:]

        init(suites: [UserDefaultsSuite: [String: Any]] = [:]) {
            self.suites = suites
        }

        /// How many observers are registered.
        var observerCount: Int {
            observers.count
        }

        func values(in suite: UserDefaultsSuite) -> [String: Any] {
            reads += 1
            onRead?()
            return suites[suite, default: [:]]
        }

        /// Every key of the suite: the fake keeps no global domain or registered defaults.
        func ownKeys(in suite: UserDefaultsSuite) -> Set<String> {
            Set(suites[suite, default: [:]].keys)
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
