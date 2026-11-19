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
        private let box = AccessibilityModelBox()
    #endif

    public init() {}

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
            AccessibilityInstallation.drawers.insert(ObjectIdentifier(drawer))
        #endif
    }

    /// Clears every override (``AccessibilityOverrides/reset()``) once no drawer holds the plugin,
    /// so the views under `.debugAccessibilityOverrides()` get the system's values again.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            guard AccessibilityInstallation.drawers.remove(ObjectIdentifier(drawer)) != nil,
                  AccessibilityInstallation.drawers.isEmpty
            else { return }
            box.model.perform(AccessibilityCommand(.reset))
        #endif
    }
}

#if DEBUG
    /// The drawers holding the Accessibility plugin; its overrides apply while there is one.
    @MainActor
    enum AccessibilityInstallation {
        static var drawers: Set<ObjectIdentifier> = []
    }

    // The plugin's initializer isn't isolated (a host may make the plugin anywhere) and the model
    // is on the main actor, so the plugin holds this box, which makes the model the first time the
    // view or a hook, both on the main actor, asks for it. Rejected: a `@MainActor` initializer on
    // the plugin (a source break for a host making it off the main actor), and `AccessibilityModel`
    // made in a nonisolated initializer (it subscribes to its services as it is made).

    /// Holds the Accessibility plugin's model, made when first asked for.
    @MainActor
    final class AccessibilityModelBox {
        nonisolated init() {}

        /// The plugin's model, over ``AccessibilityOverrides/shared`` and the device's settings.
        private(set) lazy var model = AccessibilityModel()
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
