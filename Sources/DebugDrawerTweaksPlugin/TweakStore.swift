#if DEBUG
    import Combine

    /// The tweaks' values, read and written through a ``TweakStorage``.
    ///
    /// Main-actor isolated, like the drawer that edits it: the app reads tweaks from its views and
    /// its startup code, and a value read elsewhere is one hop away. If tweaks come to be read on
    /// hot paths off the main thread, a `Mutex`-guarded cache would replace the isolation.
    @MainActor
    final class TweakStore: ObservableObject {
        /// The store `Tweak.value` reads, over the storage `installTweaks` was given (the standard
        /// defaults until then).
        static let shared = TweakStore(storage: UserDefaultsTweakStorage())

        private(set) var storage: any TweakStorage
        /// Each change, as the key and the value now stored, for the tweaks' publishers.
        private let changes = PassthroughSubject<(key: String, value: TweakStoredValue?), Never>()

        init(storage: some TweakStorage) {
            self.storage = storage
        }

        /// Reads and writes through `storage` from now on.
        func use(_ storage: some TweakStorage) {
            objectWillChange.send()
            self.storage = storage
        }

        func value<Value>(of tweak: Tweak<Value>) -> Value {
            tweak.value(from: storage.value(forKey: tweak.key))
        }

        func set<Value>(_ value: Value, for tweak: Tweak<Value>) {
            setStoredValue(tweak.storedValue(of: value), forKey: tweak.key)
        }

        /// The value stored for `key`, if any.
        func storedValue(forKey key: String) -> TweakStoredValue? {
            storage.value(forKey: key)
        }

        /// Stores `value` for `key`; `nil` resets the tweak to its default.
        func setStoredValue(_ value: TweakStoredValue?, forKey key: String) {
            objectWillChange.send()
            storage.setValue(value, forKey: key)
            changes.send((key, value))
        }

        /// Resets each of `keys` to its tweak's default.
        func reset(keys: [String]) {
            for key in keys {
                setStoredValue(nil, forKey: key)
            }
        }

        func publisher<Value>(for tweak: Tweak<Value>) -> AnyPublisher<Value, Never> {
            changes
                .filter { $0.key == tweak.key }
                .map { tweak.value(from: $0.value) }
                .prepend(value(of: tweak))
                .removeDuplicates()
                .eraseToAnyPublisher()
        }
    }
#endif
