#if DEBUG
    import SwiftUI

    // MARK: - Drawer overlay view

    /// The actual drawer panel rendered as an overlay.
    struct DebugDrawerOverlay: View {
        @ObservedObject var drawer: DebugDrawer
        /// Tracks which plugins the user has *collapsed*. Everything starts expanded.
        @State private var collapsedSections: Set<String> = []
        /// What the search field holds; results show while it isn't empty.
        @State private var query = ""
        /// The result Return runs, moved by the arrow keys.
        @State private var highlighted = 0
        @FocusState private var searchFocused: Bool

        private let drawerWidth: CGFloat = 340
        private let defaultsPrefix = "com.debugdrawer.collapsed."

        var body: some View {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Spacer()

                    if drawer.isOpen {
                        ScrollViewReader { proxy in
                            VStack(spacing: 0) {
                                header
                                searchField(proxy)
                                if !query.isEmpty {
                                    searchResults(proxy)
                                }
                                Divider()
                                content
                            }
                        }
                        // Cmd-K exists only inside the open drawer, so it never opens it (N2).
                        .background {
                            Button("Search Plugins") { searchFocused = true }
                                .keyboardShortcut("k", modifiers: .command)
                                .hidden()
                        }
                        .frame(width: drawerWidth)
                        .background(.ultraThickMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .shadow(color: .black.opacity(0.25), radius: 12, x: -4)
                        .padding(.top, max(8, geometry.safeAreaInsets.top))
                        .padding(.bottom, max(8, geometry.safeAreaInsets.bottom))
                        .padding(.trailing, 8)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .ignoresSafeArea()
            .onAppear { loadCollapsedState() }
        }

        private var allPlugins: [AnyDebugDrawerPlugin] {
            drawer.localPlugins + drawer.globalPlugins
        }

        private func loadCollapsedState() {
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

        // MARK: - Search

        private func searchField(_ proxy: ScrollViewProxy) -> some View {
            TextField("Search plugins and actions", text: $query)
                .textFieldStyle(.roundedBorder)
                .controlSize(.small)
                .focused($searchFocused)
                .onChange(of: query) { highlighted = 0 }
                .onSubmit { chooseHighlighted(proxy) }
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onKeyPress(.escape) {
                    guard !query.isEmpty else { return .ignored }
                    query = ""
                    return .handled
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 8)
        }

        private func searchResults(_ proxy: ScrollViewProxy) -> some View {
            let found = DrawerSearchResult.matches(query, in: allPlugins)
            return VStack(spacing: 0) {
                if found.isEmpty {
                    Text("No matches")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                }
                // Offsets, not ids: two actions of one plugin may share a title.
                ForEach(Array(found.enumerated()), id: \.offset) { index, result in
                    Button { choose(result, proxy) } label: {
                        resultRow(result, isHighlighted: index == highlighted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 6)
        }

        private func resultRow(_ result: DrawerSearchResult, isHighlighted: Bool) -> some View {
            HStack(spacing: 8) {
                Image(systemName: result.icon)
                    .frame(width: 20)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(result.title)
                        .font(.subheadline)
                    if let pluginTitle = result.pluginTitle {
                        Text(pluginTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
            .background(isHighlighted ? Color.accentColor.opacity(0.15) : .clear)
            .contentShape(Rectangle())
        }

        private func moveHighlight(by step: Int) -> KeyPress.Result {
            let count = DrawerSearchResult.matches(query, in: allPlugins).count
            guard count > 0 else { return .ignored }
            highlighted = min(max(highlighted + step, 0), count - 1)
            return .handled
        }

        private func chooseHighlighted(_ proxy: ScrollViewProxy) {
            let found = DrawerSearchResult.matches(query, in: allPlugins)
            guard found.indices.contains(highlighted) else { return }
            choose(found[highlighted], proxy)
        }

        /// Jumps to and expands a plugin, or runs an action, and clears the search.
        private func choose(_ result: DrawerSearchResult, _ proxy: ScrollViewProxy) {
            query = ""
            searchFocused = false
            switch result {
            case let .plugin(plugin):
                expand(plugin)
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(plugin.id, anchor: .top)
                }
            case let .action(action, _):
                action.perform()
            }
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

        private func expand(_ plugin: AnyDebugDrawerPlugin) {
            guard collapsedSections.contains(plugin.id) else { return }
            toggleExpanded(plugin)
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
            .id(plugin.id)
        }
    }

    // MARK: - Root modifier (attach once at app level)

    struct DebugDrawerModifier: ViewModifier {
        @ObservedObject var drawer = DebugDrawer.shared

        func body(content: Content) -> some View {
            content
                .overlay(alignment: .trailing) {
                    DebugDrawerOverlay(drawer: drawer)
                        .accessibilityIdentifier(debugDrawerOverlayIdentifier)
                        .background(DebugDrawerTagView())
                        .allowsHitTesting(drawer.isOpen)
                }
                .animation(.easeInOut(duration: 0.25), value: drawer.isOpen)
        }
    }

    // MARK: - Platform view tagger

    /// Tags the nearest platform view with a known tag so the a11y auditor
    /// can skip the debug drawer subtree without relying on class names.
    public let debugDrawerViewTag = 0xDDB6 // "DDB" = DebugDrawerBoundary

    #if os(macOS)
        struct DebugDrawerTagView: NSViewRepresentable {
            func makeNSView(context _: Context) -> NSView {
                let v = NSView()
                v.setAccessibilityIdentifier(debugDrawerOverlayIdentifier)
                return v
            }

            func updateNSView(_: NSView, context _: Context) {}
        }
    #elseif os(iOS)
        struct DebugDrawerTagView: UIViewRepresentable {
            func makeUIView(context _: Context) -> UIView {
                let v = UIView()
                v.tag = debugDrawerViewTag
                v.accessibilityIdentifier = debugDrawerOverlayIdentifier
                return v
            }

            func updateUIView(_: UIView, context _: Context) {}
        }
    #endif

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
        /// Place once at the root of your view hierarchy. While the drawer is open, Cmd-K focuses its
        /// search field, which finds plugins and their ``DebugDrawerPlugin/actions``.
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
