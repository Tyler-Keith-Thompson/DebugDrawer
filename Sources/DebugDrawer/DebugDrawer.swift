#if DEBUG
    import os
    import SwiftUI

    /// The accessibility identifier on the drawer's overlay, which tells the drawer's views apart
    /// from the app's.
    let debugDrawerOverlayIdentifier = "com.debugdrawer.overlay"

    // MARK: - Central registry + state

    /// The drawer: the registry of its plugins, whether it is open, and the state it shares with
    /// them (badges, toasts, the HUD, redaction rules and the report uploader).
    ///
    /// There is one, ``shared``. **Global plugins** live for the app's lifetime: register them
    /// once at startup with ``registerGlobal(_:)``. **Local plugins** follow a view's lifetime:
    /// attach them with `debugLocalPlugin(_:)`, which registers on appear and unregisters on
    /// disappear.
    ///
    /// ```swift
    /// DebugDrawer.shared.registerGlobal(BuildInfoPlugin())
    /// DebugDrawer.shared.toggle()
    /// ```
    ///
    /// Release builds get a stand-in with the same members that holds nothing: registering
    /// drops the plugin and toggling opens nothing, so code that calls the drawer compiles
    /// unchanged there.
    @MainActor
    public final class DebugDrawer: ObservableObject {
        /// The app's drawer, which `debugDrawer()` shows and every plugin registers with.
        public static let shared = DebugDrawer()

        /// Where the drawer reports registrations it can't honor, such as two plugin types under
        /// one ID.
        static let logger = Logger(subsystem: "DebugDrawer", category: "DebugDrawer")

        /// Whether the key window's drawer is on screen. Set it, or call ``toggle()``.
        ///
        /// Each window has a drawer of its own, open or closed apart from the others; this is the
        /// one in the key window (on iOS, the scene in front), or, with none attached yet, the
        /// drawer the next window attached opens with.
        @Published public var isOpen = false {
            didSet {
                guard !isSyncingOpenState, isOpen != keyPresentation.isOpen else { return }
                keyPresentation.isOpen = isOpen
            }
        }

        /// True while ``isOpen`` is being set from the key window's drawer, so the change isn't
        /// passed back to it.
        var isSyncingOpenState = false

        /// Bring ``isOpen`` up to date when another window becomes key, and on iOS detach a scene's
        /// drawer when the scene disconnects; added on the first attach.
        var windowObservers: [any NSObjectProtocol] = []

        /// The drawer of each window attached with `attach(to:)`, in the order they were attached.
        var attachments: [DrawerAttachment] = []

        /// The drawer of no window: the one tvOS, visionOS and watchOS draw in the app's own
        /// window, and elsewhere the state the first window attached takes on.
        let detachedPresentation = DrawerPresentation()

        /// The plugins registered with ``registerGlobal(_:)``, in the order they were registered.
        @Published public private(set) var globalPlugins: [AnyDebugDrawerPlugin] = []

        /// The plugins attached with `debugLocalPlugin(_:)` whose views are on screen, in every
        /// window, in the order they first appeared.
        ///
        /// Each window's drawer lists only the local plugins registered from views in that window,
        /// and those registered with ``registerLocal(_:)``, which belong to no window.
        @Published public private(set) var localPlugins: [AnyDebugDrawerPlugin] = []

        /// Every local plugin's registration: its token and the window whose views registered it.
        var localRegistrations: [DrawerLocalRegistration] = [] {
            didSet { localPlugins = localRegistrations.map(\.plugin) }
        }

        /// Where the drawer saves what it keeps across launches: the HUD's layout, which plugins'
        /// notices are silenced, and each window's collapsed sections, pins and order.
        let defaults: UserDefaults

        /// Makes a drawer that saves to `defaults`; the app's is ``shared``, saving to the drawer's
        /// own suite (`UserDefaults.debugDrawer`) so none of it shows among the app's defaults.
        /// Tests pass a suite of their own so nothing they save reaches another test or the app.
        init(defaults: UserDefaults = .debugDrawer) {
            self.defaults = defaults
            hudLayout = HUDLayout(from: defaults)
            noticesMutedPlugins = Set(defaults.stringArray(forKey: Self.noticesMutedDefaultsKey) ?? [])
        }

        // MARK: - Global

        /// Registers a plugin that stays in the drawer for the app's lifetime.
        ///
        /// A plugin whose ``DebugDrawerPlugin/id`` is already registered as global is ignored; when
        /// the plugin registered under that ID is of another type, the drawer also logs an error
        /// naming both types, since one of them needs an ``DebugDrawerPlugin/id`` of its own.
        ///
        /// - Parameter plugin: The plugin to add.
        public func registerGlobal<P: DebugDrawerPlugin>(_ plugin: P) {
            let wrapped = AnyDebugDrawerPlugin(plugin)
            switch DrawerRegistrationOutcome(of: wrapped, among: globalPlugins) {
            case .added:
                adoptSavedState(of: wrapped)
                globalPlugins.append(wrapped)
            case .alreadyRegistered:
                break
            case let .collision(registered):
                Self.logger.error("""
                A global plugin of type \(wrapped.typeName, privacy: .public) wasn't registered: \
                \(registered.typeName, privacy: .public) is registered under its id \(wrapped.id, privacy: .public). \
                Give one of them an id of its own.
                """)
            }
        }

        /// Removes the global plugin with this ID; does nothing if there is none.
        ///
        /// - Parameter id: The plugin's ``DebugDrawerPlugin/id``.
        public func unregisterGlobal(id: String) {
            globalPlugins.removeAll { $0.id == id }
        }

        // MARK: - Local

        /// Registers a plugin tied to a view, listed in every window's drawer, replacing any local
        /// plugin with the same ID registered this way.
        ///
        /// `debugLocalPlugin(_:)` registers its plugin for the window its view is in; call this
        /// directly only to tie a plugin to something other than a SwiftUI view.
        ///
        /// - Parameter plugin: The plugin to add.
        /// - Returns: The token that owns the registration; pass it to
        ///   ``unregisterLocal(id:token:)``. Only the latest registration's token removes the plugin.
        @discardableResult
        public func registerLocal<P: DebugDrawerPlugin>(_ plugin: P) -> UUID {
            registerLocal(plugin, scope: nil)
        }

        /// Registers a plugin for the drawer of the window `scope` identifies (every window's when
        /// `nil`), replacing a plugin with the same ID registered for that window.
        ///
        /// - Returns: The token that owns the registration.
        func registerLocal(_ plugin: some DebugDrawerPlugin, scope: ObjectIdentifier?) -> UUID {
            let token = UUID()
            place(DrawerLocalRegistration(token: token, plugin: AnyDebugDrawerPlugin(plugin), scope: scope))
            return token
        }

        /// Shows `plugin` as the latest value of the registration `token` owns: its views follow it
        /// at once, and the drawer lists it anew only when its ID, title, icon, category or
        /// actions changed. Does nothing once `token` no longer owns a registration.
        func updateLocal(_ plugin: some DebugDrawerPlugin, token: UUID) {
            guard let registration = localRegistrations.first(where: { $0.token == token }) else { return }
            let latest = AnyDebugDrawerPlugin(plugin)
            if latest.isListed(like: registration.content.plugin) {
                registration.content.plugin = latest
            } else {
                place(DrawerLocalRegistration(token: token, plugin: latest, scope: registration.scope))
            }
        }

        /// Puts `registration` in the list, replacing the one with its token, or else the one of the
        /// same ID in the same window, and logs an error when that one is of another type.
        private func place(_ registration: DrawerLocalRegistration) {
            let plugin = registration.plugin
            let replaced = localRegistrations.first { $0.token != registration.token && $0.plugin.id == plugin.id && $0.scope == registration.scope }
            if let replaced, replaced.plugin.typeName != plugin.typeName {
                Self.logger.error("""
                A local plugin of type \(plugin.typeName, privacy: .public) replaced one of type \
                \(replaced.plugin.typeName, privacy: .public) registered under the same id \(plugin.id, privacy: .public). \
                Give one of them an id of its own.
                """)
            }
            if !localRegistrations.contains(where: { $0.token == registration.token || $0.plugin.id == plugin.id }) {
                adoptSavedState(of: plugin)
            }
            localRegistrations = localRegistrations.placing(registration)
        }

        /// Moves the registration `token` owns to the drawer of the window `scope` identifies, as
        /// its view learns which window it is in.
        func moveLocal(token: UUID, to scope: ObjectIdentifier?) {
            guard var registration = localRegistrations.first(where: { $0.token == token }), registration.scope != scope else { return }
            registration.scope = scope
            localRegistrations = localRegistrations.placing(registration)
        }

        /// The local plugins the drawer of the window `scope` identifies lists: those registered
        /// from its views and from no window, each ID once.
        func localPlugins(listedIn scope: ObjectIdentifier?) -> [AnyDebugDrawerPlugin] {
            localRegistrations.plugins(listedIn: scope)
        }

        /// Removes a local plugin if `token` is its current registration's.
        ///
        /// A view that disappears after a newer view registered the same plugin holds a stale
        /// token, so the newer registration stays.
        ///
        /// - Parameters:
        ///   - id: The plugin's ``DebugDrawerPlugin/id``.
        ///   - token: What ``registerLocal(_:)`` returned.
        public func unregisterLocal(id: String, token: UUID) {
            localRegistrations.removeAll { $0.token == token && $0.plugin.id == id }
        }

        /// Whether there are any plugins registered at all.
        public var hasPlugins: Bool {
            !globalPlugins.isEmpty || !localPlugins.isEmpty
        }

        // MARK: - Redaction

        /// What plugins mask in copies, exports and, until revealed, on screen. Starts as
        /// ``DebugDrawerRedaction/standard``; assign ``DebugDrawerRedaction/none`` to mask nothing.
        @Published public var redaction = DebugDrawerRedaction.standard

        /// Masks more header names, keys containing these patterns, and JSON paths, on top of
        /// the current rules.
        ///
        /// - Parameters:
        ///   - headers: Header names to mask, matched without regard to case.
        ///   - keys: Patterns that mask any key containing one, without regard to case.
        ///   - jsonPaths: Dotted paths into JSON bodies to mask.
        public func redact(
            headers: some Sequence<String> = [String](),
            keys: some Sequence<String> = [String](),
            jsonPaths: some Sequence<String> = [String]()
        ) {
            redaction = redaction.adding(headers: headers, keys: keys, jsonPaths: jsonPaths)
        }

        // MARK: - Report upload

        /// What sends a finished bug report to the team; the drawer shows Send Report only while
        /// one is set. Starts as nil: reports stay on the device and the library sends nothing.
        @Published public var reportUploader: (any DebugDrawerReportUploader)?

        // MARK: - HUD

        /// Which plugins are pinned to the floating HUD, and where it sits. Saved in `UserDefaults`.
        @Published public internal(set) var hudLayout: HUDLayout

        /// Whether the HUD is hidden for a moment, as while ``performWhileHidden(drawer:_:)`` runs.
        @Published public internal(set) var isHUDHidden = false

        /// Pins the plugin's readout to the HUD, or removes it if it is pinned, and saves the change.
        ///
        /// - Parameter id: The plugin's ``DebugDrawerPlugin/id``.
        public func toggleHUD(forPlugin id: String) {
            hudLayout.togglePin(id)
            hudLayout.save(to: defaults)
        }

        /// Moves the HUD's top-leading corner to `origin` and saves it.
        ///
        /// - Parameter origin: The new corner, in the window's coordinates.
        public func moveHUD(to origin: CGPoint) {
            hudLayout.origin = origin
            hudLayout.save(to: defaults)
        }

        /// The registered plugins pinned to the HUD that offer one, in the order they were pinned.
        public var hudPlugins: [AnyDebugDrawerPlugin] {
            let plugins = localPlugins + globalPlugins
            return hudLayout.pinned.compactMap { id in plugins.first { $0.id == id && $0.hasHUD } }
        }

        // MARK: - Badges and toasts

        /// Badge counts shown on plugins' section headers, by plugin ID.
        @Published public internal(set) var badges: [String: Int] = [:]

        /// The notice shown while the drawer is closed, if a plugin has raised one.
        @Published public internal(set) var toast: DebugDrawerToast?

        /// The IDs of the plugins whose badges and toasts are silenced, saved in ``defaults``.
        @Published var noticesMutedPlugins: Set<String>
    }
#else
    import SwiftUI

    // The release stand-in: the same members, so the host's code compiles unchanged, and no drawer
    // behind them. It registers nothing, opens nothing and keeps every value at its start.

    /// Release builds have no drawer: this stand-in keeps the debug build's members and does nothing.
    @MainActor
    public final class DebugDrawer: ObservableObject {
        /// The stand-in drawer.
        public static let shared = DebugDrawer()

        /// Always false: release builds have no drawer to open.
        @Published public var isOpen = false

        /// Always empty: registering drops the plugin.
        @Published public private(set) var globalPlugins: [AnyDebugDrawerPlugin] = []

        /// Always empty: registering drops the plugin.
        @Published public private(set) var localPlugins: [AnyDebugDrawerPlugin] = []

        private init() {}

        /// Drops the plugin: release builds have no drawer.
        ///
        /// - Parameter plugin: Ignored.
        public func registerGlobal<P: DebugDrawerPlugin>(_ plugin: P) {}

        /// Does nothing.
        ///
        /// - Parameter id: Ignored.
        public func unregisterGlobal(id: String) {}

        /// Drops the plugin: release builds have no drawer.
        ///
        /// - Parameter plugin: Ignored.
        /// - Returns: A token that unregisters nothing.
        @discardableResult
        public func registerLocal<P: DebugDrawerPlugin>(_ plugin: P) -> UUID {
            UUID()
        }

        /// Does nothing.
        ///
        /// - Parameters:
        ///   - id: Ignored.
        ///   - token: Ignored.
        public func unregisterLocal(id: String, token: UUID) {}

        /// Does nothing: release builds have no drawer to open.
        public func toggle() {}

        /// Runs `action`: there is no drawer or HUD to hide.
        ///
        /// - Parameters:
        ///   - hidesDrawer: Ignored.
        ///   - action: The work to do.
        public func performWhileHidden(drawer hidesDrawer: Bool = true, _ action: @escaping @MainActor () async -> Void) {
            Task { await action() }
        }

        /// Always false.
        public var hasPlugins: Bool {
            false
        }

        /// The rules plugins would mask with; nothing reads them in release.
        @Published public var redaction = DebugDrawerRedaction.standard

        /// Does nothing: nothing in release masks anything.
        ///
        /// - Parameters:
        ///   - headers: Ignored.
        ///   - keys: Ignored.
        ///   - jsonPaths: Ignored.
        public func redact(
            headers: some Sequence<String> = [String](),
            keys: some Sequence<String> = [String](),
            jsonPaths: some Sequence<String> = [String]()
        ) {}

        /// Kept, never called: release builds make no reports.
        @Published public var reportUploader: (any DebugDrawerReportUploader)?

        /// Always empty: release builds have no HUD.
        @Published public internal(set) var hudLayout = HUDLayout()

        /// Always false.
        @Published public internal(set) var isHUDHidden = false

        /// Does nothing.
        ///
        /// - Parameter id: Ignored.
        public func toggleHUD(forPlugin id: String) {}

        /// Does nothing.
        ///
        /// - Parameter origin: Ignored.
        public func moveHUD(to origin: CGPoint) {}

        /// Always empty.
        public var hudPlugins: [AnyDebugDrawerPlugin] {
            []
        }

        /// Always empty.
        @Published public private(set) var badges: [String: Int] = [:]

        /// Always nil.
        @Published public private(set) var toast: DebugDrawerToast?
    }
#endif
