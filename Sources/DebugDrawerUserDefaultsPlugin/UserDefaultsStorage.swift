#if DEBUG
    import Combine
    import Foundation

    /// The suites' values, read and written, and word of a change to any of them.
    @MainActor
    protocol UserDefaultsStorage {
        /// The keys and values `suite` finds in `domain`.
        func values(in suite: UserDefaultsSuite, domain: DefaultsDomain) -> [String: Any]
        /// Writes `value`, a property-list object, for `key` in `suite`'s persistent domain.
        func set(_ value: Any, forKey key: String, in suite: UserDefaultsSuite)
        /// Removes `key` from `suite`'s persistent domain.
        func removeValue(forKey key: String, in suite: UserDefaultsSuite)
        /// Calls `onChange`, on whichever thread wrote, after any suite in the process changes,
        /// until the returned value is cancelled or released.
        func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyCancellable
    }

    /// The real defaults: `standard` for the standard defaults, and `UserDefaults(suiteName:)` for
    /// a named suite. A name UserDefaults refuses (the app's own bundle identifier, or
    /// `NSGlobalDomain`) reads as empty and ignores writes.
    struct _UserDefaultsStorage: UserDefaultsStorage {
        /// The standard defaults.
        let standard: UserDefaults
        /// The name of the standard defaults' persistent domain.
        let standardDomainName: String

        /// - Parameters:
        ///   - standard: The defaults the Standard suite reads and writes.
        ///   - standardDomainName: The name of `standard`'s persistent domain: the app's bundle
        ///     identifier, or the process name when it has none; a suite's name for a suite.
        init(
            standard: UserDefaults = .standard,
            standardDomainName: String = Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName
        ) {
            self.standard = standard
            self.standardDomainName = standardDomainName
        }

        func values(in suite: UserDefaultsSuite, domain: DefaultsDomain) -> [String: Any] {
            guard let defaults = defaults(for: suite) else { return [:] }
            switch domain {
            case .persistent:
                return defaults.persistentDomain(forName: domainName(of: suite)) ?? [:]
            case .argument:
                return defaults.volatileDomain(forName: UserDefaults.argumentDomain)
            case .registration:
                return defaults.volatileDomain(forName: UserDefaults.registrationDomain)
            case .global:
                // The search list's other domains, the global domain for this host among them,
                // have no public name to read them by, so they are what the merged view holds
                // beyond the three named ones.
                let named = [DefaultsDomain.persistent, .argument, .registration].map { values(in: suite, domain: $0) }
                return defaults.dictionaryRepresentation().filter { key, _ in
                    !named.contains { $0[key] != nil }
                }
            }
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
            case .standard: standard
            case let .named(name): UserDefaults(suiteName: name)
            }
        }

        private func domainName(of suite: UserDefaultsSuite) -> String {
            switch suite {
            case .standard: standardDomainName
            case let .named(name): name
            }
        }
    }
#endif
