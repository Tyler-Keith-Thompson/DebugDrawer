#if DEBUG
    /// What a reset did to one category.
    enum ResetOutcome: Hashable, Sendable {
        /// Everything listed was deleted: this many items (keys, keychain items, entries,
        /// cookies; one for the URL cache and the app's cleanup).
        case cleared(Int)
        /// Some of it was deleted and some couldn't be.
        case failed(cleared: Int, failures: [ResetFailure])
    }

    /// Something a reset couldn't delete, and why.
    enum ResetFailure: Hashable, Sendable {
        /// The keychain couldn't be read, so nothing in it was deleted.
        case keychainUnavailable(KeychainError)
        /// A keychain item, by name, that the keychain wouldn't delete.
        case keychainItem(String, KeychainError)
        /// A file, by its path in its area, that couldn't be deleted.
        case file(String, reason: String)
        /// The app's own cleanup threw.
        case cleanup(String)

        /// What the drawer says.
        var message: String {
            switch self {
            case let .keychainUnavailable(error): "The keychain couldn't be read: \(error.message)"
            case let .keychainItem(name, error): "\(name): \(error.message)"
            case let .file(path, reason): "\(path): \(reason)"
            case let .cleanup(reason): "The app's cleanup failed: \(reason)"
            }
        }
    }

    /// What a reset did, category by category.
    struct ResetResult: Hashable, Sendable {
        /// Each reset category's outcome; categories that weren't selected have none.
        let outcomes: [ResetCategory: ResetOutcome]

        /// Whether anything failed.
        var hasFailures: Bool {
            outcomes.values.contains { if case .failed = $0 { true } else { false } }
        }

        /// The categories reset, in the drawer's order.
        var categories: [ResetCategory] {
            ResetCategory.allCases.filter { outcomes[$0] != nil }
        }
    }
#endif
