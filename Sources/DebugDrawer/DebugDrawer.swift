#if DEBUG
    import SwiftUI

    // MARK: - Central registry + state

    /// Central registry for debug drawer plugins and visibility state.
    ///
    /// **Global plugins** live for the app's lifetime — register them once at startup.
    /// **Local plugins** are tied to a view's lifecycle — use the `.debugLocalPlugin()` modifier.
    /// Accessibility identifier used on the drawer overlay.
    /// Auditors and other tools should skip views inside this subtree.
    public let debugDrawerOverlayIdentifier = "com.debugdrawer.overlay"

    @MainActor
    public final class DebugDrawer: ObservableObject {
        public static let shared = DebugDrawer()

        @Published public var isOpen = false
        @Published public private(set) var globalPlugins: [AnyDebugDrawerPlugin] = []
        @Published public private(set) var localPlugins: [AnyDebugDrawerPlugin] = []

        /// Tracks the token that owns each local plugin registration.
        /// When a new view registers with the same plugin ID, it gets a new token.
        /// The old view's onDisappear checks the token — if it doesn't match, the
        /// unregister is a no-op (the new view already claimed it).
        var localTokens: [String: UUID] = [:]

        private init() {}

        // MARK: - Global

        /// Register a global plugin. Always visible in the drawer. Duplicate IDs are ignored.
        public func registerGlobal<P: DebugDrawerPlugin>(_ plugin: P) {
            guard !globalPlugins.contains(where: { $0.id == plugin.id }) else { return }
            globalPlugins.append(AnyDebugDrawerPlugin(plugin))
        }

        /// Remove a global plugin by ID.
        public func unregisterGlobal(id: String) {
            globalPlugins.removeAll { $0.id == id }
        }

        // MARK: - Local

        /// Register a local plugin (called by the view modifier on appear).
        /// If a plugin with the same ID already exists, it is replaced.
        /// Returns a token that the caller must pass to `unregisterLocal` —
        /// only the current owner can remove the plugin.
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

        /// Remove a local plugin, but only if the token matches the current registration.
        /// This prevents a stale view's onDisappear from removing a plugin that a new view
        /// already re-registered.
        public func unregisterLocal(id: String, token: UUID) {
            guard localTokens[id] == token else { return }
            localTokens.removeValue(forKey: id)
            localPlugins.removeAll { $0.id == id }
        }

        // MARK: - Visibility

        /// Toggle drawer visibility.
        public func toggle() {
            withAnimation(Self.motion(.easeInOut(duration: 0.25))) {
                isOpen.toggle()
            }
        }

        /// Hide the drawer, run an async action, then reopen it.
        /// Useful for screenshots or any operation that needs a clean view.
        public func performWhileHidden(_ action: @escaping @MainActor () async -> Void) {
            let wasOpen = isOpen
            guard wasOpen else {
                Task { await action() }
                return
            }

            withAnimation(Self.motion(.easeInOut(duration: 0.15))) {
                self.isOpen = false
            } completion: { [weak self] in
                Task { @MainActor [weak self] in
                    await action()
                    withAnimation(Self.motion(.easeInOut(duration: 0.25))) {
                        self?.isOpen = true
                    }
                }
            }
        }

        /// `animation`, or none when the user asked the system to reduce motion. The drawer is not a
        /// view, so it reads the system setting rather than `\.accessibilityReduceMotion`.
        private static func motion(_ animation: Animation) -> Animation? {
            debugDrawerSystemReduceMotion ? nil : animation
        }

        /// Whether there are any plugins registered at all.
        public var hasPlugins: Bool {
            !globalPlugins.isEmpty || !localPlugins.isEmpty
        }

        // MARK: - Badges and toasts

        /// Badge counts shown on plugins' section headers, by plugin ID.
        @Published public private(set) var badges: [String: Int] = [:]

        /// The notice shown while the drawer is closed, if a plugin has raised one.
        @Published public private(set) var toast: DebugDrawerToast?

        /// A plugin the overlay should expand and scroll to the next time it can.
        @Published var revealRequest: String?

        /// Shows `count` on the plugin's section header; zero or less clears it.
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
#endif
