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

    /// A declaration `installTweaks` can't show, which it refuses rather than show a control
    /// that can't hold its own default.
    public enum InvalidTweaks: Error, Equatable, Sendable {
        /// Two tweaks share a key, so they would share a stored value.
        case duplicateKey
        /// A string picker's default isn't one of its options, or it has none.
        case pickerDefaultNotAnOption
        /// A stepper's default is outside its range.
        case stepperDefaultOutOfRange
        /// A stepper's step is 0 or less.
        case stepperStepNotPositive
    }

    public var title = "Tweaks"
    public var category = "App"
    public var icon = "slider.horizontal.3"

    #if DEBUG
        let sections: [TweakSection]
        /// The values the plugin shows and edits: the shared store `Tweak.value` reads, unless
        /// given another.
        let store: TweakStore

        /// - Parameters:
        ///   - sections: The sections, in the order shown.
        ///   - store: The values to show and edit.
        /// - Throws: ``InvalidTweaks`` when two tweaks in `sections` share a key, or one can't hold
        ///   its own default.
        init(sections: [TweakSection], store: TweakStore = .shared) throws(InvalidTweaks) {
            let tweaks = sections.flatMap(\.tweaks)
            guard Set(tweaks.map(\.key)).count == tweaks.count else { throw .duplicateKey }
            for tweak in tweaks {
                try tweak.checkDefault()
            }
            self.sections = sections
            self.store = store
        }
    #endif

    public var body: some View {
        #if DEBUG
            TweaksPluginView(sections: sections, store: store)
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
    ///     ``/DebugDrawerTweaks/UserDefaultsTweakStorage/defaultKeyPrefix``, unless given.
    ///   - sections: The sections, in the order shown.
    /// - Throws: `TweaksPlugin.InvalidTweaks` when two tweaks in `sections` share a key, a
    ///   picker's default isn't one of its options, or a stepper's default is outside its range or
    ///   its step isn't positive, installing nothing. Release builds install nothing and throw
    ///   nothing.
    func installTweaks(
        storage: some TweakStorage = UserDefaultsTweakStorage(),
        @TweakSectionBuilder _ sections: () -> [TweakSection]
    ) throws(TweaksPlugin.InvalidTweaks) {
        #if DEBUG
            let plugin = try TweaksPlugin(sections: sections())
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

    extension AnyTweak {
        /// Throws when the tweak's control can't hold its default: a picker's default not among
        /// its options, a stepper's outside its range or a step that isn't positive.
        fileprivate func checkDefault() throws(TweaksPlugin.InvalidTweaks) {
            switch control {
            case let .picker(options):
                guard options.contains(where: { $0.value == defaultValue }) else { throw .pickerDefaultNotAnOption }
            case let .stepper(range, step):
                guard let value = defaultValue.int, range.contains(value) else { throw .stepperDefaultOutOfRange }
                guard step > 0 else { throw .stepperStepNotPositive }
            case .toggle, .text:
                return
            }
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
