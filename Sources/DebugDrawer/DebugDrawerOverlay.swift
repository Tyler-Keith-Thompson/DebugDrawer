#if DEBUG
    import SwiftUI

    // MARK: - Drawer overlay view

    /// The actual drawer panel rendered as an overlay.
    struct DebugDrawerOverlay: View {
        @ObservedObject var drawer: DebugDrawer
        /// Tracks which plugins the user has *collapsed*. Everything starts expanded.
        @State private var collapsedSections: Set<String> = []

        private let drawerWidth: CGFloat = 340
        private let defaultsPrefix = "com.debugdrawer.collapsed."

        var body: some View {
            HStack(spacing: 0) {
                Spacer()

                if drawer.isOpen {
                    VStack(spacing: 0) {
                        header
                        Divider()
                        content
                    }
                    .frame(width: drawerWidth)
                    .background(.ultraThickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .shadow(color: .black.opacity(0.25), radius: 12, x: -4)
                    .padding(.vertical, 8)
                    .padding(.trailing, 8)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .onAppear { loadCollapsedState() }
        }

        private func loadCollapsedState() {
            let allPlugins = drawer.localPlugins + drawer.globalPlugins
            for plugin in allPlugins {
                if UserDefaults.standard.bool(forKey: defaultsPrefix + plugin.id) {
                    collapsedSections.insert(plugin.id)
                }
            }
        }

        // MARK: - Header

        private var header: some View {
            HStack {
                Image(systemName: "ladybug")
                    .foregroundStyle(.orange)
                Text("Debug")
                    .font(.headline)
                Spacer()
                Button(action: { drawer.toggle() }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }

        // MARK: - Plugin list

        private var content: some View {
            ScrollView {
                if !drawer.hasPlugins {
                    emptyState
                } else {
                    LazyVStack(spacing: 0) {
                        // Local plugins first — contextual tools take precedence
                        if !drawer.localPlugins.isEmpty {
                            sectionHeader("Local")
                            ForEach(drawer.localPlugins) { plugin in
                                pluginSection(plugin)
                            }
                        }

                        // Global plugins
                        if !drawer.globalPlugins.isEmpty {
                            sectionHeader("Global")
                            ForEach(drawer.globalPlugins) { plugin in
                                pluginSection(plugin)
                            }
                        }
                    }
                }
            }
        }

        private func sectionHeader(_ title: String) -> some View {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }

        private var emptyState: some View {
            VStack(spacing: 8) {
                Image(systemName: "tray")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                Text("No plugins registered")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }

        private func isExpanded(_ plugin: AnyDebugDrawerPlugin) -> Bool {
            !collapsedSections.contains(plugin.id)
        }

        private func toggleExpanded(_ plugin: AnyDebugDrawerPlugin) {
            withAnimation(.easeInOut(duration: 0.2)) {
                let key = defaultsPrefix + plugin.id
                if collapsedSections.contains(plugin.id) {
                    collapsedSections.remove(plugin.id)
                    UserDefaults.standard.removeObject(forKey: key)
                } else {
                    collapsedSections.insert(plugin.id)
                    UserDefaults.standard.set(true, forKey: key)
                }
            }
        }

        private func pluginSection(_ plugin: AnyDebugDrawerPlugin) -> some View {
            let expanded = isExpanded(plugin)

            return VStack(spacing: 0) {
                Button(action: { toggleExpanded(plugin) }) {
                    HStack(spacing: 8) {
                        Image(systemName: plugin.icon)
                            .frame(width: 20)
                            .foregroundStyle(.secondary)
                        Text(plugin.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if expanded {
                    plugin.body
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Divider().padding(.leading, 14)
            }
        }
    }

    // MARK: - Root modifier (attach once at app level)

    struct DebugDrawerModifier: ViewModifier {
        @ObservedObject var drawer = DebugDrawer.shared

        func body(content: Content) -> some View {
            content
                .overlay(alignment: .trailing) {
                    DebugDrawerOverlay(drawer: drawer)
                }
                .animation(.easeInOut(duration: 0.25), value: drawer.isOpen)
                .background {
                    Button("") { drawer.toggle() }
                        .keyboardShortcut("d", modifiers: .control)
                        .hidden()
                }
        }
    }

    // MARK: - Local plugin modifier

    /// Attaches a local plugin to this view's lifecycle.
    /// The plugin appears in the drawer when this view is on screen
    /// and is removed when the view disappears — but only if no newer
    /// view has already replaced the registration.
    ///
    /// Re-registers automatically when the plugin's `contentIdentifier` changes,
    /// so this works regardless of where `.id()` is placed in the chain.
    struct LocalPluginModifier<P: DebugDrawerPlugin>: ViewModifier {
        let plugin: P
        @State private var token: UUID?

        func body(content: Content) -> some View {
            content
                .onAppear {
                    token = DebugDrawer.shared.registerLocal(plugin)
                }
                .onDisappear {
                    if let token {
                        DebugDrawer.shared.unregisterLocal(id: plugin.id, token: token)
                    }
                }
                .onChange(of: plugin.contentIdentifier) { _, _ in
                    token = DebugDrawer.shared.registerLocal(plugin)
                }
        }
    }

    // MARK: - Public API

    public extension View {
        /// Attaches the debug drawer overlay to this view.
        /// Place once at the root of your view hierarchy. Toggle with Ctrl+D.
        func debugDrawer() -> some View {
            modifier(DebugDrawerModifier())
        }

        /// Registers a local debug plugin that is active while this view is on screen.
        func debugLocalPlugin<P: DebugDrawerPlugin>(_ plugin: P) -> some View {
            modifier(LocalPluginModifier(plugin: plugin))
        }
    }
#else
    import SwiftUI

    public extension View {
        func debugDrawer() -> some View {
            self
        }

        func debugLocalPlugin<P: DebugDrawerPlugin>(_: P) -> some View {
            self
        }
    }
#endif
