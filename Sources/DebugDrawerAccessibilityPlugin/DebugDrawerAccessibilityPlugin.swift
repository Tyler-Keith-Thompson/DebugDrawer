import DebugDrawer
import SwiftUI

// MARK: - Plugin

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and an installer that registers nothing.

/// Overrides of the color scheme, Dynamic Type, layout direction, locale and the system
/// accessibility settings SwiftUI reads, for the views under `.debugAccessibilityOverrides()`.
public struct AccessibilityPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public nonisolated var id: String {
        "AccessibilityPlugin"
    }

    public var title = "Accessibility"
    public var category = "Interface"
    public var icon = "accessibility"

    #if DEBUG
        /// The plugin's own model, which its view and hooks reach.
        private let box: AccessibilityModelBox

        /// The plugin over ``AccessibilityOverrides/shared``, which `.debugAccessibilityOverrides()`
        /// applies.
        public init() {
            box = AccessibilityModelBox()
        }

        /// - Parameter model: The model to show and drive, over overrides of its own.
        init(model: AccessibilityModel) {
            box = AccessibilityModelBox(model: model)
        }
    #else
        public init() {}
    #endif

    public var body: some View {
        #if DEBUG
            AccessibilityPluginView(transport: .direct(to: box.model))
        #else
            EmptyView()
        #endif
    }

    /// Counts `drawer` as holding the plugin, so its overrides stay until the last drawer removes
    /// it. Release builds override nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            AccessibilityInstallation.install(box.model.overrides, in: drawer)
        #endif
    }

    /// Clears every override (``AccessibilityOverrides/reset()``) once no drawer holds the plugin,
    /// so the views under `.debugAccessibilityOverrides()` get the system's values again.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            guard AccessibilityInstallation.uninstall(box.model.overrides, from: drawer) else { return }
            box.model.perform(AccessibilityCommand(.reset))
        #endif
    }
}

#if DEBUG
    // Counted by the overrides rather than by the plugin's model: every plugin made with `init()`
    // has a model of its own, all over `AccessibilityOverrides.shared`, so a drawer removing one
    // must not clear what another drawer's plugin still shows.

    /// The drawers holding an Accessibility plugin, by the overrides it edits; each set of
    /// overrides applies while a drawer holds a plugin over it.
    @MainActor
    enum AccessibilityInstallation {
        private static var drawers: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]

        /// Counts `drawer` as holding a plugin over `overrides`.
        static func install(_ overrides: any AccessibilityOverrideStore, in drawer: DebugDrawer) {
            drawers[ObjectIdentifier(overrides), default: []].insert(ObjectIdentifier(drawer))
        }

        /// Uncounts `drawer`.
        ///
        /// - Returns: Whether `drawer` held a plugin over `overrides` and no other drawer does now.
        static func uninstall(_ overrides: any AccessibilityOverrideStore, from drawer: DebugDrawer) -> Bool {
            let key = ObjectIdentifier(overrides)
            guard drawers[key]?.remove(ObjectIdentifier(drawer)) != nil else { return false }
            guard drawers[key]?.isEmpty == true else { return false }
            drawers[key] = nil
            return true
        }
    }

    // The plugin's initializer isn't isolated (a host may make the plugin anywhere) and the model
    // is on the main actor, so the plugin holds this box, which makes the model the first time the
    // view or a hook, both on the main actor, asks for it. Rejected: a `@MainActor` initializer on
    // the plugin (a source break for a host making it off the main actor), and `AccessibilityModel`
    // made in a nonisolated initializer (it subscribes to its services as it is made).

    /// Holds the Accessibility plugin's model, made when first asked for.
    @MainActor
    final class AccessibilityModelBox {
        /// The model given at init, if any.
        private let given: AccessibilityModel?

        /// A box that makes a model over ``AccessibilityOverrides/shared`` when first asked.
        nonisolated init() {
            given = nil
        }

        /// A box holding `model`.
        init(model: AccessibilityModel) {
            given = model
        }

        /// The plugin's model: the one given, or one over ``AccessibilityOverrides/shared`` and
        /// the device's settings.
        private(set) lazy var model = given ?? AccessibilityModel()
    }
#endif

// MARK: - Convenience installer

public extension DebugDrawer {
    /// Registers the Accessibility plugin. Its overrides apply to the views under
    /// `.debugAccessibilityOverrides()`.
    func installAccessibility() {
        #if DEBUG
            registerGlobal(AccessibilityPlugin())
        #endif
    }
}
