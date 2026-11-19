import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that installs nothing.

/// The host's own debug settings: the tweaks and actions `installTweaks(storage:_:)` was
/// given, in their sections.
public struct TweaksPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public nonisolated var id: String {
        "TweaksPlugin"
    }

    public var title = "Tweaks"
    public var category = "App"
    public var icon = "slider.horizontal.3"

    #if DEBUG
        let sections: [TweakSection]

        /// - Precondition: No two tweaks in `sections` share a key, since they would share a
        ///   stored value.
        init(sections: [TweakSection]) {
            let keys = sections.flatMap(\.tweaks).map(\.key)
            precondition(Set(keys).count == keys.count, "Two tweaks share a key")
            self.sections = sections
        }
    #endif

    public var body: some View {
        #if DEBUG
            TweaksPluginView(sections: sections, store: .shared)
        #else
            EmptyView()
        #endif
    }

    /// Has nothing to stop or drop. The storage `installTweaks(storage:_:)` gave stays in use:
    /// the app reads its tweaks' values through it whether or not the drawer lists the plugin,
    /// and going back to the default storage would change what it reads. Stored values stay.
    @MainActor public func uninstall(from drawer: DebugDrawer) {}

    /// Each section's actions, found by their titles or their section's.
    public var actions: [DebugDrawerAction] {
        #if DEBUG
            sections.flatMap { section in
                section.actions.map { action in
                    DebugDrawerAction(action.title, keywords: [section.title], perform: action.perform)
                }
            }
        #else
            []
        #endif
    }
}

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
        #if DEBUG
            let plugin = TweaksPlugin(sections: sections())
            unregisterGlobal(id: plugin.id)
            TweakStore.shared.use(storage)
            registerGlobal(plugin)
        #endif
    }
}

#if DEBUG
    // MARK: - Plugin

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

#endif
