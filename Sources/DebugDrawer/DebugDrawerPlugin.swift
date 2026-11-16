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
    associatedtype HUD: View = EmptyView
    associatedtype HeaderAccessory: View = EmptyView

    /// Identifies the plugin in the drawer: registration, saved state and search. Defaults to the
    /// type's name; declare one to register several instances of one type.
    var id: String { get }

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

    /// A compact readout the developer can pin to the floating HUD, which stays on screen while the
    /// drawer is closed. Defaults to none.
    @MainActor var hud: HUD? { get }

    // A view rather than a value (counts and a summary) so it follows the plugin's own store,
    // which the drawer doesn't observe, and can hold an action; the issue count is vocabulary so
    // every header draws one alike. Rejected: a `DebugDrawerHeaderSummary` value (no live updates
    // without the drawer observing each plugin, and a Copy action would need a case of its own),
    // an optional like `hud` (an `EmptyView` default needs no `nil` and reads the same), and
    // reusing the badge (it counts what's new and the drawer clears it on open).

    /// A compact readout at the trailing edge of the plugin's header row, shown whether the
    /// plugin is open or closed: what it has found (``DebugDrawerIssueCount``), a short summary
    /// (`Text("1,204 lines")`), or a borderless action such as Copy. Text in it is set in the
    /// drawer's monospaced code type in the tertiary color unless it names another; it keeps to
    /// one line. Built on the main actor like ``body``, so it follows the plugin's state as the
    /// body does. Defaults to none.
    ///
    /// A plugin with an accessory has no numeric badge in its header: the accessory replaces it,
    /// and the dot on its navigator tab still marks what's new.
    @ViewBuilder @MainActor var headerAccessory: HeaderAccessory { get }
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

public extension DebugDrawerPlugin where HUD == EmptyView {
    /// No HUD: the plugin can't be pinned to the floating HUD.
    var hud: EmptyView? {
        nil
    }
}

public extension DebugDrawerPlugin where HeaderAccessory == EmptyView {
    /// No header accessory: the header shows the title, pin and badge alone.
    var headerAccessory: EmptyView {
        EmptyView()
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
        private let _hud: (@MainActor () -> AnyView)?
        private let _headerAccessory: (@MainActor () -> AnyView)?
        private let _contribute: (@MainActor (inout DebugDrawerReport, DebugDrawerRedaction) -> Void)?

        @MainActor public init<P: DebugDrawerPlugin>(_ plugin: P) {
            id = plugin.id
            title = plugin.title
            icon = plugin.icon
            category = plugin.category
            actions = plugin.actions
            _body = { AnyView(plugin.body) }
            if plugin.hud == nil {
                _hud = nil
            } else {
                _hud = { AnyView(plugin.hud) }
            }
            if P.HeaderAccessory.self == EmptyView.self {
                _headerAccessory = nil
            } else {
                _headerAccessory = { AnyView(plugin.headerAccessory) }
            }
            if let contributor = plugin as? any DebugDrawerReportContributor {
                _contribute = { contributor.contribute(to: &$0, redaction: $1) }
            } else {
                _contribute = nil
            }
        }

        /// Whether the plugin adopts ``DebugDrawerReportContributor``, and so adds files to the
        /// bug report.
        public var contributesToReport: Bool {
            _contribute != nil
        }

        /// Adds the plugin's files to `report`; a plugin that doesn't adopt
        /// ``DebugDrawerReportContributor`` adds nothing.
        @MainActor public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            _contribute?(&report, redaction)
        }

        @MainActor public var body: AnyView {
            _body()
        }

        /// Whether the plugin offers a HUD readout.
        public var hasHUD: Bool {
            _hud != nil
        }

        /// The plugin's HUD readout, if it offers one.
        @MainActor public var hud: AnyView? {
            _hud?()
        }

        /// The plugin's header accessory, if it declares one.
        @MainActor public var headerAccessory: AnyView? {
            _headerAccessory?()
        }

        /// Whether the plugin declares a header accessory, without building it.
        var hasHeaderAccessory: Bool {
            _headerAccessory != nil
        }

        /// The `UserDefaults` key that records whether the user collapsed this plugin's section.
        var collapsedStateKey: String {
            "com.debugdrawer.collapsed." + id
        }
    }
#endif
