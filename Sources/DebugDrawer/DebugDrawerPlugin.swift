import SwiftUI

// MARK: - Plugin protocol

// Main actor on the protocol rather than on each requirement: everything that reads a plugin
// (registration, the drawer, `AnyDebugDrawerPlugin`, its views and hooks) already runs there, and
// per-requirement isolation would leave `id`, `title`, `icon`, `category` and `actions` readable
// from any thread while the drawer never reads them off the main actor.

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
/// A plugin that starts work of its own adopts the lifecycle hooks: the drawer calls
/// ``install(in:)`` as it adds the plugin, ``didBecomeVisible(in:)`` and ``didBecomeHidden(in:)``
/// as its content comes on and leaves the screen, and ``uninstall(from:)`` as it removes it.
///
/// ``id`` defaults to the type's fully qualified name (`MyApp.CachePlugin`), so two modules'
/// plugins of one name are told apart. The drawer saves whether each plugin's section is
/// collapsed, and where it is pinned, under its ``id``, in a `UserDefaults` suite of its own
/// rather than the app's.
///
/// The protocol is isolated to the main actor, as the drawer and SwiftUI views are: a plugin
/// is made, registered and read there.
///
/// The protocol exists in every build so conformances compile everywhere. In release builds
/// `debugLocalPlugin(_:)` and `debugDrawer()` return the view unchanged, and nothing reads the
/// plugin.
@MainActor
public protocol DebugDrawerPlugin: Identifiable {
    /// The type of the view the plugin shows in its section.
    associatedtype Body: View
    /// The type of the plugin's HUD readout; `EmptyView` for a plugin with none.
    associatedtype HUD: View = EmptyView
    /// The type of the plugin's header accessory; `EmptyView` for a plugin with none.
    associatedtype HeaderAccessory: View = EmptyView

    /// Identifies the plugin in the drawer: registration, saved state and search. Defaults to the
    /// type's fully qualified name (`String(reflecting:)`, such as `MyApp.CachePlugin`; a
    /// `private` or function-local type is named as if it were declared in its module); declare
    /// one to register several instances of one type.
    ///
    /// The drawer holds one global plugin per ID: registering a plugin of another type under an
    /// ID already registered leaves the first in place and logs an error.
    var id: String { get }

    /// Display title shown in the section header.
    var title: String { get }

    /// SF Symbol name for the section header icon.
    var icon: String { get }

    /// The view content rendered inside the section, built on the main actor like `View.body`.
    @ViewBuilder @MainActor var body: Body { get }

    /// Unused: `debugLocalPlugin(_:)` shows the plugin's latest value each time its view
    /// updates, so nothing needs to say when the content changed. Defaults to ``id``.
    @available(*, deprecated, message: "Unused: debugLocalPlugin(_:) shows the plugin's latest value as its view updates")
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

    // Lifecycle. "Visible" is the plugin's content on screen (its section's body in an open
    // drawer, shown alone, or its HUD readout), not the drawer being open: a monitor can then run
    // only while someone can see what it measures, and a collapsed section costs nothing.
    // Rejected: visible while any drawer is open (a collapsed or scrolled-past plugin would keep
    // working) and one `lifecycle(_ event:)` method taking an enum (a plugin would switch over
    // cases it ignores, and a new case would break every exhaustive switch).

    /// Called once when `drawer` adds the plugin, after it is listed: start what the plugin needs
    /// while it is in the drawer, such as a monitor or an interception. Defaults to nothing.
    ///
    /// A drawer calls it once per registration: ``DebugDrawer/registerGlobal(_:)`` for a global
    /// plugin, the first appearance of its view for a local one. Every call is matched by one
    /// ``uninstall(from:)``.
    ///
    /// - Parameter drawer: The drawer that now holds the plugin.
    @MainActor func install(in drawer: DebugDrawer)

    /// Called once when `drawer` removes the plugin, after it is no longer listed and after
    /// ``didBecomeHidden(in:)`` if it was on screen: stop what ``install(in:)`` started.
    /// Defaults to nothing.
    ///
    /// - Parameter drawer: The drawer that held the plugin.
    @MainActor func uninstall(from drawer: DebugDrawer)

    /// Called when the plugin's content comes on screen in `drawer`: its section's body in an open
    /// drawer, the plugin shown alone, or its readout on the HUD. Called once however many windows
    /// show it, and again only after ``didBecomeHidden(in:)``. Defaults to nothing.
    ///
    /// - Parameter drawer: The drawer showing the plugin.
    @MainActor func didBecomeVisible(in drawer: DebugDrawer)

    /// Called when the last of the plugin's content leaves the screen in `drawer` (the drawer
    /// closed, the section collapsed, the readout unpinned), or when the drawer removes the plugin
    /// while it is on screen. Defaults to nothing.
    ///
    /// - Parameter drawer: The drawer that showed the plugin.
    @MainActor func didBecomeHidden(in drawer: DebugDrawer)
}

public extension DebugDrawerPlugin {
    // Nonisolated: it witnesses `Identifiable.id`, which isn't isolated to the main actor.
    /// The type's fully qualified name, such as `MyApp.CachePlugin`.
    nonisolated var id: String {
        qualifiedName(of: type(of: self))
    }

    /// ``id``: nothing reads it.
    @available(*, deprecated, message: "Unused: debugLocalPlugin(_:) shows the plugin's latest value as its view updates")
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

    /// Does nothing: the plugin starts nothing when a drawer adds it.
    @MainActor func install(in drawer: DebugDrawer) {}

    /// Does nothing: the plugin has nothing to stop when a drawer removes it.
    @MainActor func uninstall(from drawer: DebugDrawer) {}

    /// Does nothing.
    @MainActor func didBecomeVisible(in drawer: DebugDrawer) {}

    /// Does nothing.
    @MainActor func didBecomeHidden(in drawer: DebugDrawer) {}
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

// `String(reflecting:)` writes such a context as `(unknown context at $1029a4c80).`, an address
// that moves between launches, which would lose the plugin's saved state at every launch.
/// `type`'s fully qualified name (`MyApp.Screen.CachePlugin`) without the contexts Swift can't
/// name: a `private` type or one declared in a function is `MyApp.CachePlugin`.
func qualifiedName(of type: Any.Type) -> String {
    String(reflecting: type).replacing(#/\(unknown context at \$[0-9a-fA-F]+\)\./#, with: "")
}

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
    /// The plugin's type, fully qualified: two registrations of one ID from different types
    /// collide.
    let typeName: String
    /// The type's unqualified name, when the plugin takes the default ``DebugDrawerPlugin/id``:
    /// a name the drawer's saved state may still be keyed by, which it moves to ``id``.
    let unqualifiedTypeID: String?
    // Internal rather than private: a local plugin's wrapper builds them to read its latest value
    // (LocalPluginContent).
    let makeBody: @MainActor () -> AnyView
    let makeHUD: (@MainActor () -> AnyView)?
    let makeHeaderAccessory: (@MainActor () -> AnyView)?
    let contributeToReport: (@MainActor (inout DebugDrawerReport, DebugDrawerRedaction) -> Void)?
    /// The plugin's install, uninstall and visibility hooks, which the drawer calls.
    let lifecycle: DrawerPluginLifecycle

    /// Wraps `plugin`, reading its properties now and keeping it to build its views later.
    ///
    /// - Parameter plugin: The plugin to wrap.
    @MainActor public init<P: DebugDrawerPlugin>(_ plugin: P) {
        id = plugin.id
        title = plugin.title
        icon = plugin.icon
        category = plugin.category
        actions = plugin.actions
        typeName = String(reflecting: P.self)
        unqualifiedTypeID = plugin.id == qualifiedName(of: P.self) ? String(describing: P.self) : nil
        makeBody = { AnyView(plugin.body) }
        if plugin.hud == nil {
            makeHUD = nil
        } else {
            makeHUD = { AnyView(plugin.hud) }
        }
        if P.HeaderAccessory.self == EmptyView.self {
            makeHeaderAccessory = nil
        } else {
            makeHeaderAccessory = { AnyView(plugin.headerAccessory) }
        }
        if let contributor = plugin as? any DebugDrawerReportContributor {
            contributeToReport = { contributor.contribute(to: &$0, redaction: $1) }
        } else {
            contributeToReport = nil
        }
        lifecycle = DrawerPluginLifecycle(plugin)
    }

    /// Whether the plugin adopts ``DebugDrawerReportContributor``, and so adds files to the
    /// bug report.
    public var contributesToReport: Bool {
        contributeToReport != nil
    }

    /// Adds the plugin's files to `report`; a plugin that doesn't adopt
    /// ``DebugDrawerReportContributor`` adds nothing.
    @MainActor public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
        contributeToReport?(&report, redaction)
    }

    /// The plugin's ``DebugDrawerPlugin/body``, built now.
    @MainActor public var body: AnyView {
        makeBody()
    }

    /// Whether the plugin offers a HUD readout.
    public var hasHUD: Bool {
        makeHUD != nil
    }

    /// The plugin's HUD readout, if it offers one.
    @MainActor public var hud: AnyView? {
        makeHUD?()
    }

    /// The plugin's header accessory, if it declares one.
    @MainActor public var headerAccessory: AnyView? {
        makeHeaderAccessory?()
    }

    /// Whether the plugin declares a header accessory, without building it.
    var hasHeaderAccessory: Bool {
        makeHeaderAccessory != nil
    }

    /// The `UserDefaults` key that records whether the user collapsed this plugin's section.
    var collapsedStateKey: String {
        Self.collapsedStateKey(forID: id)
    }

    /// The `UserDefaults` key that records whether the user collapsed the section of the plugin
    /// with ID `id`.
    static func collapsedStateKey(forID id: String) -> String {
        "com.debugdrawer.collapsed." + id
    }
}
