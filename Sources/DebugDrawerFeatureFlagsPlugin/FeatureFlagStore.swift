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
        /// The drawers the plugin is installed in; the stored overrides are applied to the
        /// provider while there is one.
        private var installations: Set<ObjectIdentifier> = []

        /// A store over `provider` and `storage`. Nothing is applied to `provider` until
        /// ``install(in:)``.
        init(provider: some FeatureFlagProvider, storage: some FeatureFlagOverrideStorage) {
            self.provider = provider
            self.storage = storage
        }

        /// Counts `drawer` as one the plugin is installed in; the first one applies every stored
        /// override to the provider, so the app reads them from its next read on.
        func install(in drawer: ObjectIdentifier) {
            guard installations.insert(drawer).inserted, installations.count == 1 else { return }
            // Sorted, so the adapter sees the same calls in the same order every launch.
            for (key, value) in storage.overrides().sorted(by: { $0.key < $1.key }) {
                provider.setOverride(value, forKey: key)
            }
        }

        /// Uncounts `drawer`; once no drawer holds the plugin, clears every stored override from
        /// the provider, so the app reads the live values again. The overrides stay in storage
        /// for the next install.
        func uninstall(from drawer: ObjectIdentifier) {
            guard installations.remove(drawer) != nil, installations.isEmpty else { return }
            for key in storage.overrides().keys.sorted() {
                provider.clearOverride(forKey: key)
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
