import SwiftUI

// MARK: - Plugin protocol

/// A plugin that contributes a section to the debug drawer.
///
/// Conform to this protocol to register custom debug panels.
/// Each plugin gets its own collapsible section in the drawer.
///
/// Plugins come in two flavors:
/// - **Global**: registered once via `DebugDrawer.shared.registerGlobal()`, always present.
/// - **Local**: attached to a view via `.debugLocalPlugin()`, present only while that view is.
///
/// The protocol exists in all builds so conformances compile everywhere.
/// In release builds, `.debugLocalPlugin()` and `.debugDrawer()` are no-ops.
///
/// `id` is auto-derived from the type name — you don't need to provide one.
/// The drawer persists each plugin's expand/collapse state via UserDefaults.
public protocol DebugDrawerPlugin: Identifiable {
    associatedtype Body: View

    /// Display title shown in the section header.
    var title: String { get }

    /// SF Symbol name for the section header icon.
    var icon: String { get }

    /// The view content rendered inside the section, built on the main actor like `View.body`.
    @ViewBuilder @MainActor var body: Body { get }

    /// A value that changes when the plugin's content should be re-registered.
    /// The local plugin modifier watches this to detect changes.
    /// Defaults to `id` (static). Override for plugins with dynamic data
    /// (e.g., a file path that changes as the user navigates).
    var contentIdentifier: String { get }

    /// The group the plugin is listed under in the drawer. Defaults to `General`, listed last.
    var category: String { get }

    /// Actions the drawer's search field offers, run when the user picks one. Defaults to none.
    var actions: [DebugDrawerAction] { get }
}

public extension DebugDrawerPlugin {
    /// Stable identifier derived from the concrete type name.
    var id: String {
        String(describing: type(of: self))
    }

    /// Defaults to `id` — override when the plugin carries dynamic state.
    var contentIdentifier: String {
        id
    }

    /// `General`: the group for plugins that name no category.
    var category: String {
        defaultPluginCategory
    }

    /// No actions: the search field finds the plugin by its title only.
    var actions: [DebugDrawerAction] {
        []
    }
}

/// The category of a plugin that names none.
let defaultPluginCategory = "General"

#if DEBUG

    // MARK: - Type-erased wrapper

    /// Type-erased wrapper so the drawer can hold heterogeneous plugins.
    public struct AnyDebugDrawerPlugin: Identifiable {
        public let id: String
        public let title: String
        public let icon: String
        public let category: String
        public let actions: [DebugDrawerAction]
        private let _body: @MainActor () -> AnyView

        @MainActor public init<P: DebugDrawerPlugin>(_ plugin: P) {
            id = plugin.id
            title = plugin.title
            icon = plugin.icon
            category = plugin.category
            actions = plugin.actions
            _body = { AnyView(plugin.body) }
        }

        @MainActor public var body: AnyView {
            _body()
        }
    }
#endif
