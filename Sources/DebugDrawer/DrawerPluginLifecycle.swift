/// A plugin's lifecycle hooks, kept by its type-erased wrapper so the drawer can call them.
struct DrawerPluginLifecycle {
    /// The plugin's ``DebugDrawerPlugin/install(in:)``.
    let install: @MainActor (DebugDrawer) -> Void
    /// The plugin's ``DebugDrawerPlugin/uninstall(from:)``.
    let uninstall: @MainActor (DebugDrawer) -> Void
    /// The plugin's ``DebugDrawerPlugin/didBecomeVisible(in:)``.
    let didBecomeVisible: @MainActor (DebugDrawer) -> Void
    /// The plugin's ``DebugDrawerPlugin/didBecomeHidden(in:)``.
    let didBecomeHidden: @MainActor (DebugDrawer) -> Void

    /// The hooks of `plugin`.
    @MainActor init(_ plugin: some DebugDrawerPlugin) {
        install = { plugin.install(in: $0) }
        uninstall = { plugin.uninstall(from: $0) }
        didBecomeVisible = { plugin.didBecomeVisible(in: $0) }
        didBecomeHidden = { plugin.didBecomeHidden(in: $0) }
    }

    /// The hooks given.
    init(
        install: @escaping @MainActor (DebugDrawer) -> Void,
        uninstall: @escaping @MainActor (DebugDrawer) -> Void,
        didBecomeVisible: @escaping @MainActor (DebugDrawer) -> Void,
        didBecomeHidden: @escaping @MainActor (DebugDrawer) -> Void
    ) {
        self.install = install
        self.uninstall = uninstall
        self.didBecomeVisible = didBecomeVisible
        self.didBecomeHidden = didBecomeHidden
    }
}
