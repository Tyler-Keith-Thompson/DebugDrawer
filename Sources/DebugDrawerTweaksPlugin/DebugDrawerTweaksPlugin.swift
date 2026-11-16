#if DEBUG
    import DebugDrawer
    import SwiftUI

    // MARK: - Plugin

    /// The host's own debug settings: the tweaks and actions `installTweaks(storage:_:)` was
    /// given, in their sections.
    public struct TweaksPlugin: DebugDrawerPlugin {
        public var title = "Tweaks"
        public var category = "App"
        public var icon = "slider.horizontal.3"

        let sections: [TweakSection]

        /// - Precondition: No two tweaks in `sections` share a key, since they would share a
        ///   stored value.
        init(sections: [TweakSection]) {
            let keys = sections.flatMap(\.tweaks).map(\.key)
            precondition(Set(keys).count == keys.count, "Two tweaks share a key")
            self.sections = sections
        }

        public var body: some View {
            TweaksPluginView(sections: sections, store: .shared)
        }

        /// Each section's actions, found by their titles or their section's.
        public var actions: [DebugDrawerAction] {
            sections.flatMap { section in
                section.actions.map { action in
                    DebugDrawerAction(action.title, keywords: [section.title], perform: action.perform)
                }
            }
        }
    }

    /// Reads the store and hands its values to `TweaksView`.
    struct TweaksPluginView: View {
        let sections: [TweakSection]
        @ObservedObject var store: TweakStore

        var body: some View {
            TweaksView(
                sections: sections.map { TweakSectionState($0, stored: store.storedValue(forKey:)) },
                onChange: { store.setStoredValue($1, forKey: $0) },
                onReset: { store.setStoredValue(nil, forKey: $0) },
                onResetAll: { store.reset(keys: sections.flatMap(\.tweaks).map(\.key)) }
            )
        }
    }

    extension TweakSection {
        var tweaks: [AnyTweak] {
            items.compactMap { if case let .tweak(tweak) = $0.kind { tweak } else { nil } }
        }

        var actions: [TweakAction] {
            items.compactMap { if case let .action(action) = $0.kind { action } else { nil } }
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        /// Adds the Tweaks plugin, showing `sections`, with values kept in `storage`.
        ///
        /// Call it once at startup, before the app reads a tweak's `value`, so reads go through
        /// `storage`. Calling it again replaces the sections and the storage.
        ///
        /// - Parameters:
        ///   - storage: Where values persist; the standard defaults, under
        ///     ``UserDefaultsTweakStorage/defaultKeyPrefix``, unless given.
        ///   - sections: The sections, in the order shown.
        /// - Precondition: No two tweaks in `sections` share a key.
        func installTweaks(
            storage: some TweakStorage = UserDefaultsTweakStorage(),
            @TweakSectionBuilder _ sections: () -> [TweakSection]
        ) {
            let plugin = TweaksPlugin(sections: sections())
            TweakStore.shared.use(storage)
            unregisterGlobal(id: plugin.id)
            registerGlobal(plugin)
        }
    }
#endif
