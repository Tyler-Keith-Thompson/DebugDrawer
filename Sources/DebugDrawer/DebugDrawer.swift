#if DEBUG
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

        /// The plugins attached with `debugLocalPlugin(_:)` whose views are on screen, in the order
        /// they first appeared.
        @Published public private(set) var localPlugins: [AnyDebugDrawerPlugin] = []

        /// Tracks the token that owns each local plugin registration.
        /// When a new view registers with the same plugin ID, it gets a new token.
        /// The old view's onDisappear checks the token — if it doesn't match, the
        /// unregister is a no-op (the new view already claimed it).
        var localTokens: [String: UUID] = [:]

        private init() {}

        // MARK: - Global

        /// Registers a plugin that stays in the drawer for the app's lifetime.
        ///
        /// A plugin whose ``DebugDrawerPlugin/id`` is already registered as global is ignored.
        ///
        /// - Parameter plugin: The plugin to add.
        public func registerGlobal<P: DebugDrawerPlugin>(_ plugin: P) {
            guard !globalPlugins.contains(where: { $0.id == plugin.id }) else { return }
            globalPlugins.append(AnyDebugDrawerPlugin(plugin))
        }

        /// Removes the global plugin with this ID; does nothing if there is none.
        ///
        /// - Parameter id: The plugin's ``DebugDrawerPlugin/id``.
        public func unregisterGlobal(id: String) {
            globalPlugins.removeAll { $0.id == id }
        }

        // MARK: - Local

        /// Registers a plugin tied to a view, replacing any local plugin with the same ID.
        ///
        /// `debugLocalPlugin(_:)` calls this when its view appears; call it directly only to tie a
        /// plugin to something other than a SwiftUI view.
        ///
        /// - Parameter plugin: The plugin to add.
        /// - Returns: The token that owns the registration; pass it to
        ///   ``unregisterLocal(id:token:)``. Only the latest registration's token removes the plugin.
        @discardableResult
        public func registerLocal<P: DebugDrawerPlugin>(_ plugin: P) -> UUID {
            let token = UUID()
            localTokens[plugin.id] = token
            if let idx = localPlugins.firstIndex(where: { $0.id == plugin.id }) {
                localPlugins[idx] = AnyDebugDrawerPlugin(plugin)
            } else {
                localPlugins.append(AnyDebugDrawerPlugin(plugin))
            }
            return token
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
            guard localTokens[id] == token else { return }
            localTokens.removeValue(forKey: id)
            localPlugins.removeAll { $0.id == id }
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
        @Published public internal(set) var hudLayout = HUDLayout(from: .standard)

        /// Whether the HUD is hidden for a moment, as while ``performWhileHidden(drawer:_:)`` runs.
        @Published public internal(set) var isHUDHidden = false

        /// Pins the plugin's readout to the HUD, or removes it if it is pinned, and saves the change.
        ///
        /// - Parameter id: The plugin's ``DebugDrawerPlugin/id``.
        public func toggleHUD(forPlugin id: String) {
            hudLayout.togglePin(id)
            hudLayout.save(to: .standard)
        }

        /// Moves the HUD's top-leading corner to `origin` and saves it.
        ///
        /// - Parameter origin: The new corner, in the window's coordinates.
        public func moveHUD(to origin: CGPoint) {
            hudLayout.origin = origin
            hudLayout.save(to: .standard)
        }

        /// The registered plugins pinned to the HUD that offer one, in the order they were pinned.
        public var hudPlugins: [AnyDebugDrawerPlugin] {
            let plugins = localPlugins + globalPlugins
            return hudLayout.pinned.compactMap { id in plugins.first { $0.id == id && $0.hasHUD } }
        }

        // MARK: - Badges and toasts

        /// Badge counts shown on plugins' section headers, by plugin ID.
        @Published public private(set) var badges: [String: Int] = [:]

        /// The notice shown while the drawer is closed, if a plugin has raised one.
        @Published public private(set) var toast: DebugDrawerToast?

        /// A plugin the key window's drawer should show the next time it can.
        var revealRequest: String? {
            get { keyPresentation.revealRequest }
            set { keyPresentation.revealRequest = newValue }
        }

        /// Shows `count` on the plugin's section header; zero or less clears it.
        ///
        /// - Parameters:
        ///   - count: The number to show.
        ///   - id: The plugin's ``DebugDrawerPlugin/id``.
        public func setBadge(_ count: Int, forPlugin id: String) {
            if count > 0 {
                badges[id] = count
            } else {
                badges.removeValue(forKey: id)
            }
        }

        /// Raises a toast for the plugin while the drawer is closed. A post from the plugin that
        /// already has the toast replaces its message and adds to its count, so a burst shows as
        /// one toast; a post from another plugin replaces the toast. While the drawer is open the
        /// post is dropped: the drawer is on screen, and a badge is the lasting signal.
        ///
        /// - Parameters:
        ///   - message: What the toast says.
        ///   - id: The posting plugin's ``DebugDrawerPlugin/id``.
        public func postToast(_ message: String, fromPlugin id: String) {
            guard !isOpen else { return }
            let count = toast.map { $0.pluginID == id ? $0.count + 1 : 1 } ?? 1
            toast = DebugDrawerToast(pluginID: id, message: message, count: count)
        }

        /// Removes the toast without opening the drawer.
        public func dismissToast() {
            toast = nil
        }

        /// Opens the drawer at the toast's plugin, expanded and scrolled into view, and removes the toast.
        public func openToast() {
            guard let toast else { return }
            self.toast = nil
            revealRequest = toast.pluginID
            if !isOpen { toggle() }
        }
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

        /// Does nothing.
        ///
        /// - Parameters:
        ///   - count: Ignored.
        ///   - id: Ignored.
        public func setBadge(_ count: Int, forPlugin id: String) {}

        /// Does nothing.
        ///
        /// - Parameters:
        ///   - message: Ignored.
        ///   - id: Ignored.
        public func postToast(_ message: String, fromPlugin id: String) {}

        /// Does nothing.
        public func dismissToast() {}

        /// Does nothing.
        public func openToast() {}
    }
#endif
