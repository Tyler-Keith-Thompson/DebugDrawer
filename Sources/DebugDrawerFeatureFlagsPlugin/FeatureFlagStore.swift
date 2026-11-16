#if DEBUG
    import Combine

    /// The overrides the drawer has set, kept in a ``FeatureFlagOverrideStorage`` and applied to a
    /// ``FeatureFlagProvider``.
    ///
    /// Main-actor isolated, like the drawer that edits it and the adapter it calls, which the
    /// protocol says is called on the main actor.
    @MainActor
    final class FeatureFlagStore: ObservableObject {
        let provider: any FeatureFlagProvider
        let storage: any FeatureFlagOverrideStorage

        /// A store over `provider` and `storage`, which applies every stored override to
        /// `provider`, so the app reads them from its first read on.
        init(provider: some FeatureFlagProvider, storage: some FeatureFlagOverrideStorage) {
            self.provider = provider
            self.storage = storage
            // Sorted, so the adapter sees the same calls in the same order every launch.
            for (key, value) in storage.overrides().sorted(by: { $0.key < $1.key }) {
                provider.setOverride(value, forKey: key)
            }
        }

        /// Every stored override, by flag key.
        var overrides: [String: FeatureFlagValue] {
            storage.overrides()
        }

        /// The provider's flags, each with its live value, the value the app reads and its
        /// override.
        var rows: [FeatureFlagRowState] {
            let overrides = overrides
            return provider.flags().map { flag in
                FeatureFlagRowState(
                    flag,
                    currentValue: provider.currentValue(forKey: flag.key),
                    override: overrides[flag.key]
                )
            }
        }

        /// Overrides `key` with `value`, stored and applied to the provider. A number that isn't
        /// finite is ignored, as no flag service serves one.
        func setOverride(_ value: FeatureFlagValue, forKey key: String) {
            if case let .number(number) = value, !number.isFinite { return }
            objectWillChange.send()
            storage.setOverride(value, forKey: key)
            provider.setOverride(value, forKey: key)
        }

        /// Removes the override for `key`, from storage and from the provider.
        func clearOverride(forKey key: String) {
            objectWillChange.send()
            storage.setOverride(nil, forKey: key)
            provider.clearOverride(forKey: key)
        }

        /// Removes every stored override, including any for a flag the provider no longer lists.
        func clearAllOverrides() {
            for key in overrides.keys.sorted() {
                clearOverride(forKey: key)
            }
        }

        /// Reads the provider again, for flags whose live values changed since the drawer last
        /// drew them.
        func refresh() {
            objectWillChange.send()
        }
    }
#endif
