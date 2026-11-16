import Combine

#if DEBUG
    public extension Tweak {
        /// The tweak's current value: what the drawer last set, kept across launches, or
        /// ``defaultValue`` when nothing is stored or what is stored isn't one of its values. In
        /// release, always ``defaultValue``.
        @MainActor var value: Value {
            TweakStore.shared.value(of: self)
        }

        /// The current value, then each new value as the drawer changes it, on the main thread.
        /// In release, ``defaultValue`` alone.
        @MainActor var publisher: AnyPublisher<Value, Never> {
            TweakStore.shared.publisher(for: self)
        }
    }
#else
    public extension Tweak {
        /// The tweak's current value: what the drawer last set, kept across launches, or
        /// ``defaultValue`` when nothing is stored or what is stored isn't one of its values. In
        /// release, always ``defaultValue``.
        @MainActor var value: Value {
            defaultValue
        }

        /// The current value, then each new value as the drawer changes it, on the main thread.
        /// In release, ``defaultValue`` alone.
        @MainActor var publisher: AnyPublisher<Value, Never> {
            Just(defaultValue).eraseToAnyPublisher()
        }
    }
#endif
