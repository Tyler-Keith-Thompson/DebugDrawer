#if DEBUG
    import Combine
    import os
    import SwiftUI

    /// The accessibility identifier on the drawer's overlay, which tells the drawer's views apart
    /// from the app's.
    let debugDrawerOverlayIdentifier = "com.debugdrawer.overlay"

    // MARK: - Central registry + state

    /// The drawer: the registry of its plugins, whether it is open, and the state it shares with
    /// them (badges, toasts, the HUD, redaction rules and the report uploader).
    ///
    /// The app's is ``shared``, which `debugDrawer()` shows and the plugins' `install*()` calls
    /// register with. **Global plugins** live until they are unregistered: register them once at
    /// startup with ``registerGlobal(_:)``. **Local plugins** follow a view's lifetime: attach them
    /// with `debugLocalPlugin(_:)`, which registers on appear and unregisters on disappear.
    ///
    /// Each drawer owns its plugins: it calls a plugin's ``DebugDrawerPlugin/install(in:)`` as it
    /// adds the plugin and ``DebugDrawerPlugin/uninstall(from:)`` as it removes it, and
    /// ``DebugDrawerPlugin/didBecomeVisible(in:)`` and ``DebugDrawerPlugin/didBecomeHidden(in:)``
    /// as the plugin's content comes on and leaves the screen. A drawer made with ``init()`` or
    /// ``init(defaults:)`` holds plugins of its own, apart from ``shared``'s, as a test that
    /// registers its plugin with a drawer of its own does.
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

        /// Whether the key window's drawer is on screen. Read or observe it (`$isOpen`); open and
        /// close the drawer with ``open()``, ``close()`` or ``toggle()``. Setting it is
        /// deprecated.
        ///
        /// Each window has a drawer of its own, open or closed apart from the others; this is the
        /// one in the key window (on iOS, the scene in front), or, with none attached yet, the
        /// drawer the next window attached opens with.
        @DrawerOpenState public var isOpen = false {
            // Only a caller's deprecated set gets here: the drawer's own changes set the storage.
            didSet {
                guard isOpen != keyPresentation.isOpen else { return }
                keyPresentation.isOpen = isOpen
            }
        }

        /// The storage of ``isOpen``, which the drawer sets as the key window's drawer opens and
        /// closes: without the deprecation, and without passing the change back to that drawer.
        var openState: DrawerOpenState {
            _isOpen
        }

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
        /// Each window's drawer lists only the local plugins registered from views in that window
        /// or for it with `registerLocal(_:in:)`, and those registered with ``registerLocal(_:)``,
        /// which belong to no window.
        @Published public private(set) var localPlugins: [AnyDebugDrawerPlugin] = []

        /// Every local plugin's registration: its token and the window whose views registered it.
        ///
        /// A registration whose token joins the list is installed, and one whose token leaves it
        /// is uninstalled; one moving to another window, or listed anew, keeps its token.
        var localRegistrations: [DrawerLocalRegistration] = [] {
            didSet {
                localPlugins = localRegistrations.map(\.plugin)
                let removed = oldValue.filter { old in !localRegistrations.contains { $0.token == old.token } }
                let added = localRegistrations.filter { new in !oldValue.contains { $0.token == new.token } }
                pluginsDidChange(removed: removed.map(\.plugin), added: added.map(\.plugin))
            }
        }

        /// What watches each window (on iOS and visionOS, scene) given to `registerLocal(_:in:)`
        /// close, by the window's identifier, until it does.
        var localScopeObservers: [ObjectIdentifier: any NSObjectProtocol] = [:]

        /// Where the drawer saves what it keeps across launches: the HUD's layout, which plugins'
        /// notices are silenced, and each window's collapsed sections, pins and order. A plugin's
        /// installer keeps what the plugin saves here too, so a drawer made for a test keeps it
        /// apart from ``shared``'s.
        package let defaults: UserDefaults

        /// What the shipped plugins' installers keep for this drawer, by the type that holds it.
        private var installerStates: [ObjectIdentifier: AnyObject] = [:]

        /// The object of type `State` a plugin's installer keeps for this drawer (the model its
        /// `install*()` call shows), made with `make` the first time it is asked for and handed
        /// back after.
        ///
        /// The drawer holds it for as long as the drawer lives, so a drawer made for a test keeps
        /// a model of its own, apart from ``shared``'s, and lets go of it with the drawer. One
        /// object per type: a plugin keeps everything it needs in one.
        ///
        /// - Parameter make: Makes the object, on the first call for `State` only.
        /// - Returns: The drawer's object of type `State`.
        package func installerState<State: AnyObject>(_ make: () -> State) -> State {
            let key = ObjectIdentifier(State.self)
            // The cast can't fail: only this method writes the dictionary, under `State`'s key.
            if let state = installerStates[key] as? State { return state }
            let state = make()
            installerStates[key] = state
            return state
        }

        /// How many of each plugin's views are on screen (its section's body, its view shown
        /// alone, its HUD readout), by plugin ID; a plugin with none has no entry.
        var visibleContentCounts: [String: Int] = [:]

        /// Makes a drawer with no plugins, saving what it keeps across launches (the HUD's layout,
        /// silenced notices, collapsed sections, pins and order) where ``shared`` does: the
        /// drawer's own suite, so none of it shows among the app's defaults.
        public convenience init() {
            self.init(defaults: .debugDrawer)
        }

        /// Makes a drawer with no plugins that saves what it keeps across launches to `defaults`.
        ///
        /// Pass a suite of the drawer's own: a test's, so nothing it saves reaches another test or
        /// the app, or a second drawer's, so its layout stays apart from ``shared``'s.
        ///
        /// - Parameter defaults: Where the drawer saves its state.
        public convenience init(defaults: UserDefaults) {
            // The main queue rather than the main run loop: a run loop timer waits while a menu
            // or a drag tracks the mouse, and the toast would stay up through it.
            self.init(defaults: defaults, toastScheduler: DispatchQueue.main)
        }

        /// Makes a drawer that saves to `defaults` and times its toasts on `toastScheduler`, which
        /// must run its actions on the main thread.
        ///
        /// - Parameters:
        ///   - defaults: Where the drawer saves its state.
        ///   - toastScheduler: What counts down ``toastLifetime`` after each post.
        init(defaults: UserDefaults, toastScheduler: some Scheduler) {
            self.defaults = defaults
            hudLayout = HUDLayout(from: defaults)
            noticesMutedPlugins = Set(defaults.stringArray(forKey: Self.noticesMutedDefaultsKey) ?? [])
            // Here rather than at the property: `self` can't be passed until every property is set.
            detachedPresentation.drawer = self
            toastExpiry = expireToasts(on: toastScheduler)
        }

        // MARK: - Global

        /// Registers a plugin that stays in the drawer until ``unregisterGlobal(id:)`` removes it,
        /// and calls its ``DebugDrawerPlugin/install(in:)`` once it is listed.
        ///
        /// A plugin whose ``DebugDrawerPlugin/id`` is already registered as global is ignored, and
        /// not installed again; when the plugin registered under that ID is of another type, the
        /// drawer also logs an error naming both types, since one of them needs an
        /// ``DebugDrawerPlugin/id`` of its own.
        ///
        /// - Parameter plugin: The plugin to add.
        public func registerGlobal<P: DebugDrawerPlugin>(_ plugin: P) {
            let wrapped = AnyDebugDrawerPlugin(plugin)
            switch DrawerRegistrationOutcome(of: wrapped, among: globalPlugins) {
            case .added:
                adoptSavedState(of: wrapped)
                globalPlugins.append(wrapped)
                pluginsDidChange(removed: [], added: [wrapped])
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

        /// Removes the global plugin with this ID, then calls its
        /// ``DebugDrawerPlugin/didBecomeHidden(in:)`` if it was on screen and its
        /// ``DebugDrawerPlugin/uninstall(from:)``; does nothing if there is none.
        ///
        /// - Parameter id: The plugin's ``DebugDrawerPlugin/id``.
        public func unregisterGlobal(id: String) {
            guard let index = globalPlugins.firstIndex(where: { $0.id == id }) else { return }
            let removed = globalPlugins.remove(at: index)
            pluginsDidChange(removed: [removed], added: [])
        }

        // MARK: - Local

        /// Registers a plugin tied to a view, listed in every window's drawer, replacing any local
        /// plugin with the same ID registered this way.
        ///
        /// `debugLocalPlugin(_:)` registers its plugin for the window its view is in, and
        /// `registerLocal(_:in:)` for the `NSWindow` or `UIWindowScene` it is given; call this
        /// directly only to tie a plugin to something other than a SwiftUI view or one window.
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

        /// Removes a local plugin if `token` is its current registration's, then calls its
        /// ``DebugDrawerPlugin/didBecomeHidden(in:)`` if it was on screen and its
        /// ``DebugDrawerPlugin/uninstall(from:)``.
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

        /// What keeps the toast up past ``toastLifetime``: the pointer over it, or accessibility
        /// focus on it. A subject rather than `@Published`, since no view draws it.
        let toastHolds = CurrentValueSubject<Set<DrawerToastHold>, Never>([])

        /// Removes the toast ``toastLifetime`` after its last post while nothing holds it.
        private var toastExpiry: AnyCancellable?

        /// The IDs of the plugins whose badges and toasts are silenced, saved in ``defaults``.
        @Published var noticesMutedPlugins: Set<String>
    }
#endif
