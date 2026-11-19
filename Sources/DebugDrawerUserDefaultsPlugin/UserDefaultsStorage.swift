#if DEBUG
    import Combine
    import Foundation

    // Values cross as `PropertyListValue`, not `Any`: the model then holds values only, and a
    // test's store is a dictionary of them. The real store converts at its edge, leaving out what
    // no property list can hold.

    /// The suites' values, read and written, and word of a change to any of them.
    @MainActor
    protocol UserDefaultsStorage {
        /// The keys and values `suite` finds in `domain`; a value no property list can hold is
        /// left out.
        func values(in suite: UserDefaultsSuite, domain: DefaultsDomain) -> [String: PropertyListValue]
        /// Writes `value` for `key` in `suite`'s persistent domain.
        func set(_ value: PropertyListValue, forKey key: String, in suite: UserDefaultsSuite)
        /// Removes `key` from `suite`'s persistent domain.
        func removeValue(forKey key: String, in suite: UserDefaultsSuite)
        /// Calls `onChange`, on whichever thread wrote, after any suite in the process changes,
        /// until the returned value is cancelled or released.
        func observeChanges(_ onChange: @escaping @Sendable () -> Void) -> AnyCancellable
    }
#endif
