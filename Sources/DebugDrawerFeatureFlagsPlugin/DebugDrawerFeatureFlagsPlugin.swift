import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The app's feature flags, read through the ``FeatureFlagProvider`` that
/// `installFeatureFlags(provider:storage:)` was given: each flag's live value, a local
/// override, search, an overridden-only filter and Reset All.
public struct FeatureFlagsPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public var id: String {
        "FeatureFlagsPlugin"
    }

    public var title = "Feature Flags"
    public var category = "App"
    public var icon = "flag"

    #if DEBUG
        let store: FeatureFlagStore

        init(store: FeatureFlagStore) {
            self.store = store
        }
    #endif

    public var body: some View {
        #if DEBUG
            FeatureFlagsPluginView(store: store)
        #else
            EmptyView()
        #endif
    }

    /// Applies every stored override to the provider once the first drawer holds the plugin, so
    /// the app reads them from its next read on. Release builds apply nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            store.install(in: ObjectIdentifier(drawer))
        #endif
    }

    /// Once the last drawer that held the plugin removes it, clears every stored override from
    /// the provider, so the app reads the live values again. The overrides stay in storage and
    /// are applied again by the next install.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            store.uninstall(from: ObjectIdentifier(drawer))
        #endif
    }

    /// Reset All, found by "flags" and "overrides" too.
    public var actions: [DebugDrawerAction] {
        #if DEBUG
            [
                DebugDrawerAction("Clear feature flag overrides", keywords: ["flags", "overrides", "reset"]) { [store] in
                    store.clearAllOverrides()
                }
            ]
        #else
            []
        #endif
    }
}

public extension DebugDrawer {
    /// Adds the Feature Flags plugin over `provider`, with overrides kept in `storage`, and
    /// applies every stored override to `provider`.
    ///
    /// Call it once at startup, before the app reads a flag, so the stored overrides are in
    /// place from the first read. Calling it again replaces the provider and the storage, first
    /// clearing the overrides from the provider installed before. Unregistering the plugin
    /// clears them from `provider` too; they stay in `storage`.
    ///
    /// - Parameters:
    ///   - provider: The adapter over the app's flag service.
    ///   - storage: Where overrides persist; the standard defaults, under
    ///     ``UserDefaultsFeatureFlagOverrideStorage/defaultKey``, unless given.
    func installFeatureFlags(
        provider: some FeatureFlagProvider,
        storage: some FeatureFlagOverrideStorage = UserDefaultsFeatureFlagOverrideStorage()
    ) {
        #if DEBUG
            let plugin = FeatureFlagsPlugin(store: FeatureFlagStore(provider: provider, storage: storage))
            unregisterGlobal(id: plugin.id)
            registerGlobal(plugin)
        #endif
    }
}

#if DEBUG
    // MARK: - Plugin

    /// Reads the store and hands its values to `FeatureFlagsView`, keeping the search and the
    /// filter.
    struct FeatureFlagsPluginView: View {
        @ObservedObject var store: FeatureFlagStore
        @State private var query = ""
        @State private var isOverriddenOnly = false

        var body: some View {
            FeatureFlagsView(
                rows: store.rows,
                overrideCount: store.overrides.count,
                query: $query,
                isOverriddenOnly: $isOverriddenOnly,
                onOverride: { store.setOverride($1, forKey: $0) },
                onClear: { store.clearOverride(forKey: $0) },
                onClearAll: { store.clearAllOverrides() },
                onRefresh: { store.refresh() }
            )
            // Live values change on the service's schedule, so the flags are read again each time
            // the plugin is shown.
            .onAppear { store.refresh() }
        }
    }

    // MARK: - Convenience installer

#endif
