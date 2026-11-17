import SwiftUI

// MARK: - Plugin protocol

/// A tool in the debug drawer: a title, an icon and a view, shown as a collapsible section.
///
/// A plugin needs a ``title``, an ``icon`` and a ``body``; everything else has a default.
///
/// ```swift
/// struct BuildInfoPlugin: DebugDrawerPlugin {
///     let title = "Build Info"
///     let icon = "info.circle"
///
///     var body: some View {
///         DebugDrawerSection {
///             DebugDrawerKeyValueRow("Version", value: "1.4.2 (88)")
///         }
///     }
/// }
/// ```
///
/// Plugins come in two kinds:
/// - **Global**: registered once with `DebugDrawer.shared.registerGlobal(_:)`, always present.
/// - **Local**: attached to a view with `debugLocalPlugin(_:)`, present only while that view is.
///
/// ``id`` defaults to the type's name. The drawer saves whether each plugin's section is
/// collapsed in `UserDefaults`, under its ``id``.
///
/// The protocol exists in every build so conformances compile everywhere. In release builds
/// `debugLocalPlugin(_:)` and `debugDrawer()` return the view unchanged, and nothing reads the
/// plugin.
public protocol DebugDrawerPlugin: Identifiable {
    /// The type of the view the plugin shows in its section.
    associatedtype Body: View
    /// The type of the plugin's HUD readout; `EmptyView` for a plugin with none.
    associatedtype HUD: View = EmptyView
    /// The type of the plugin's header accessory; `EmptyView` for a plugin with none.
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

// MARK: - Type-erased wrapper

/// A plugin of any type, as the drawer holds it: its properties read once, and its views
/// built on demand.
public struct AnyDebugDrawerPlugin: Identifiable {
    /// The plugin's ``DebugDrawerPlugin/id``.
    public let id: String
    /// The plugin's ``DebugDrawerPlugin/title``.
    public let title: String
    /// The plugin's ``DebugDrawerPlugin/icon``.
    public let icon: String
    /// The plugin's ``DebugDrawerPlugin/category``.
    public let category: String
    /// The plugin's ``DebugDrawerPlugin/actions``.
    public let actions: [DebugDrawerAction]
    private let _body: @MainActor () -> AnyView
    private let _hud: (@MainActor () -> AnyView)?
    private let _headerAccessory: (@MainActor () -> AnyView)?
    private let _contribute: (@MainActor (inout DebugDrawerReport, DebugDrawerRedaction) -> Void)?

    /// Wraps `plugin`, reading its properties now and keeping it to build its views later.
    ///
    /// - Parameter plugin: The plugin to wrap.
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

    /// The plugin's ``DebugDrawerPlugin/body``, built now.
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
