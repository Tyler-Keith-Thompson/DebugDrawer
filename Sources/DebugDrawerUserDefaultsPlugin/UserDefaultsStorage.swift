#if DEBUG
    import Combine
    import Foundation

    /// The suites' values, read and written, and word of a change to any of them.
    @MainActor
    protocol UserDefaultsStorage {
        /// Every key `suite` resolves and its value, the system's and the registered defaults
        /// included, as `UserDefaults.dictionaryRepresentation()` gives them.
        func values(in suite: UserDefaultsSuite) -> [String: Any]
        /// The keys a named suite's own domain holds, without the global domain's or the
        /// registered defaults; for the standard defaults, the keys of the app's domain.
        func ownKeys(in suite: UserDefaultsSuite) -> Set<String>
        /// Writes `value`, a property-list object, for `key` in `suite`.
        func set(_ value: Any, forKey key: String, in suite: UserDefaultsSuite)
        /// Removes `key` from `suite`.
        func removeValue(forKey key: String, in suite: UserDefaultsSuite)
        /// Calls `onChange`, on whichever thread wrote, after any suite in the process changes,
        /// until the returned value is cancelled or released.
        func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyCancellable
    }

    /// The real defaults: `UserDefaults.standard`, and `UserDefaults(suiteName:)` for a named
    /// suite. A name UserDefaults refuses (the app's own bundle identifier, or
    /// `NSGlobalDomain`) reads as empty and ignores writes.
    struct _UserDefaultsStorage: UserDefaultsStorage {
        func values(in suite: UserDefaultsSuite) -> [String: Any] {
            defaults(for: suite)?.dictionaryRepresentation() ?? [:]
        }

        func ownKeys(in suite: UserDefaultsSuite) -> Set<String> {
            let domain = switch suite {
            case .standard: Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
            case let .named(name): name
            }
            return Set((defaults(for: suite)?.persistentDomain(forName: domain) ?? [:]).keys)
        }

        func set(_ value: Any, forKey key: String, in suite: UserDefaultsSuite) {
            defaults(for: suite)?.set(value, forKey: key)
        }

        func removeValue(forKey key: String, in suite: UserDefaultsSuite) {
            defaults(for: suite)?.removeObject(forKey: key)
        }

        // `didChangeNotification` names the `UserDefaults` instance that wrote, not its suite, and
        // two instances of one suite are different objects, so every change is passed on and the
        // caller re-reads the suite it shows. KVO would name the key, but only of keys observed one
        // by one, which misses a key the app adds.
        func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyCancellable {
            let center = NotificationCenter.default
            let observer = center.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: nil) { _ in
                onChange()
            }
            return AnyCancellable { center.removeObserver(observer) }
        }

        private func defaults(for suite: UserDefaultsSuite) -> UserDefaults? {
            switch suite {
            case .standard: .standard
            case let .named(name): UserDefaults(suiteName: name)
            }
        }
    }
#endif
