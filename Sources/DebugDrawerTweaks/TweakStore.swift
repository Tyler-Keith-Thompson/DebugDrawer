import Combine

// Real in every build, as the receiver's tweaks capability writes through it in release. What a
// tweak reads is the build's choice: a debug build reads every tweak's stored value, as the drawer
// may have set any of them; a release build reads only a production-safe tweak's, and only once
// the app has made the tweaks capability, so a release build that never offers tweaks to a sidecar
// reads every default, as it always has, whatever a debug build of the same app left in its
// storage. Rejected: reading every production-safe tweak's stored value in
// release (the mark alone would then change what an app that never enabled the capability
// reads), and a release store that reads nothing (a sidecar's change would never reach the app).

/// The tweaks' values, read and written through a ``TweakStorage``.
///
/// Main-actor isolated, like the drawer and the receiver that edit it: the app reads tweaks from
/// its views and its startup code, and a value read elsewhere is one hop away. If tweaks come to
/// be read on hot paths off the main thread, a `Mutex`-guarded cache would replace the isolation.
@MainActor
package final class TweakStore: ObservableObject {
    /// Which tweaks' stored values a store reads.
    package enum Reading: Sendable {
        /// Every tweak's: a debug build, where the drawer edits any of them.
        case everyTweak
        /// A production-safe tweak's, once ``offerProductionSafeTweaks()`` is called; every other
        /// tweak reads its default. A release build.
        case offeredProductionSafeTweaks

        /// What this build reads.
        package static var build: Self {
            #if DEBUG
                .everyTweak
            #else
                .offeredProductionSafeTweaks
            #endif
        }
    }

    /// The store `Tweak.value` reads, over the storage `installTweaks` or the receiver's tweaks
    /// capability was given (the standard defaults until then).
    package static let shared = TweakStore(storage: UserDefaultsTweakStorage())

    package private(set) var storage: any TweakStorage
    /// Which tweaks' stored values ``value(of:)`` reads.
    package let reading: Reading
    /// Whether the app made the receiver's tweaks capability over this store.
    package private(set) var offersProductionSafeTweaks = false
    /// Each change, for the tweaks' publishers.
    private let changes = PassthroughSubject<Change, Never>()

    package init(storage: some TweakStorage, reading: Reading = .build) {
        self.storage = storage
        self.reading = reading
    }

    /// The keys whose stored value changed, each after it is stored.
    package var changedKeys: AnyPublisher<String, Never> {
        changes.map(\.key).eraseToAnyPublisher()
    }

    /// Reads and writes through `storage` from now on.
    package func use(_ storage: some TweakStorage) {
        objectWillChange.send()
        self.storage = storage
    }

    /// Lets a release build read the production-safe tweaks' stored values, as a sidecar may now
    /// change them.
    package func offerProductionSafeTweaks() {
        guard !offersProductionSafeTweaks else { return }
        objectWillChange.send()
        offersProductionSafeTweaks = true
    }

    package func value<Value>(of tweak: Tweak<Value>) -> Value {
        reading.value(of: tweak, from: storage.value(forKey: tweak.key), offered: offersProductionSafeTweaks)
    }

    package func set<Value>(_ value: Value, for tweak: Tweak<Value>) {
        setStoredValue(tweak.storedValue(of: value), forKey: tweak.key)
    }

    /// The value stored for `key`, if any.
    package func storedValue(forKey key: String) -> TweakStoredValue? {
        storage.value(forKey: key)
    }

    /// Stores `value` for `key`; `nil` resets the tweak to its default.
    package func setStoredValue(_ value: TweakStoredValue?, forKey key: String) {
        objectWillChange.send()
        storage.setValue(value, forKey: key)
        changes.send(Change(key: key, value: value, offered: offersProductionSafeTweaks))
    }

    /// Resets each of `keys` to its tweak's default.
    package func reset(keys: [String]) {
        for key in keys {
            setStoredValue(nil, forKey: key)
        }
    }

    package func publisher<Value>(for tweak: Tweak<Value>) -> AnyPublisher<Value, Never> {
        let reading = reading
        return changes
            .filter { $0.key == tweak.key }
            .map { reading.value(of: tweak, from: $0.value, offered: $0.offered) }
            .prepend(value(of: tweak))
            .removeDuplicates()
            .eraseToAnyPublisher()
    }
}

extension TweakStore {
    /// A change: the key, the value now stored and whether production-safe tweaks are offered.
    private struct Change {
        let key: String
        let value: TweakStoredValue?
        let offered: Bool
    }
}

extension TweakStore.Reading {
    /// What `tweak` reads when `stored` is stored for it: the stored value, if this reading reads
    /// it, otherwise the default.
    fileprivate func value<Value>(of tweak: Tweak<Value>, from stored: TweakStoredValue?, offered: Bool) -> Value {
        switch self {
        case .everyTweak:
            tweak.value(from: stored)
        case .offeredProductionSafeTweaks:
            tweak.isProductionSafe && offered ? tweak.value(from: stored) : tweak.defaultValue
        }
    }
}
