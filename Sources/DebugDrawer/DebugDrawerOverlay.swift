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
        /// Pins, order and the last-used plugin, loaded once and saved on every change.
        @State private var layout = DrawerLayout()
        /// The plugin at the top of the list: set to scroll there, and kept current as the user scrolls.
        @State private var scrolledID: String?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private let drawerWidth: CGFloat = 340

        var body: some View {
            GeometryReader { geometry in
                HStack(spacing: 0) {
                    Spacer()

                    if drawer.isOpen {
                        VStack(spacing: 0) {
                            header
                            searchField
                            if !query.isEmpty {
                                searchResults
                            }
                            Divider()
                            content
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
            for plugin in allPlugins where UserDefaults.standard.bool(forKey: plugin.collapsedStateKey) {
                collapsedSections.insert(plugin.id)
            }
            layout = DrawerLayout(from: .standard)
            // The list isn't on screen yet; it opens at this plugin.
            scrolledID = layout.lastUsed
        }

        /// Changes the layout and saves it.
        private func updateLayout(_ change: (inout DrawerLayout) -> Void) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                change(&layout)
            }
            layout.save(to: .standard)
        }

        // MARK: - Header

        private var header: some View {
            HStack {
                Image(systemName: "ladybug")
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)
                Text("Debug")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button {
                    drawer.toggle()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close the debug drawer")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }

        // MARK: - Search

        private var searchField: some View {
            TextField("Search plugins and actions", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search plugins and actions")
                .controlSize(.small)
                .focused($searchFocused)
                .onChange(of: query) { highlighted = 0 }
                .onSubmit { chooseHighlighted() }
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

        private var searchResults: some View {
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
                    Button { choose(result) } label: {
                        SearchResultRow(result: result, isHighlighted: index == highlighted)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.bottom, 6)
        }

        private func moveHighlight(by step: Int) -> KeyPress.Result {
            let count = DrawerSearchResult.matches(query, in: allPlugins).count
            guard count > 0 else { return .ignored }
            highlighted = min(max(highlighted + step, 0), count - 1)
            return .handled
        }

        private func chooseHighlighted() {
            let found = DrawerSearchResult.matches(query, in: allPlugins)
            guard found.indices.contains(highlighted) else { return }
            choose(found[highlighted])
        }

        /// Jumps to and expands a plugin, or runs an action, and clears the search.
        private func choose(_ result: DrawerSearchResult) {
            query = ""
            searchFocused = false
            switch result {
            case let .plugin(plugin):
                expand(plugin)
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    scrolledID = plugin.id
                }
            case let .action(action, _):
                action.perform()
            }
        }

        // MARK: - Plugin list

        private var content: some View {
            ScrollView {
                if !drawer.hasPlugins {
                    DrawerEmptyState()
                } else {
                    LazyVStack(spacing: 0) {
                        // Local plugins first — contextual tools take precedence
                        if !drawer.localPlugins.isEmpty {
                            DrawerSectionHeader(title: "Local")
                            ForEach(drawer.localPlugins) { plugin in
                                pluginSection(plugin, isGlobal: false)
                            }
                        }

                        // Global plugins: pinned first, then by category
                        ForEach(layout.sections(for: drawer.globalPlugins)) { section in
                            DrawerSectionHeader(title: section.title)
                            ForEach(section.plugins) { plugin in
                                pluginSection(plugin, isGlobal: true)
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
            }
            .scrollPosition(id: $scrolledID, anchor: .top)
            .onChange(of: scrolledID) {
                guard let scrolledID, scrolledID != layout.lastUsed else { return }
                layout.lastUsed = scrolledID
                layout.save(to: .standard)
            }
        }

        private func isExpanded(_ plugin: AnyDebugDrawerPlugin) -> Bool {
            !collapsedSections.contains(plugin.id)
        }

        private func expand(_ plugin: AnyDebugDrawerPlugin) {
            guard collapsedSections.contains(plugin.id) else { return }
            toggleExpanded(plugin)
        }

        private func toggleExpanded(_ plugin: AnyDebugDrawerPlugin) {
            updateLayout { $0.lastUsed = plugin.id }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                let key = plugin.collapsedStateKey
                if collapsedSections.contains(plugin.id) {
                    collapsedSections.remove(plugin.id)
                    UserDefaults.standard.removeObject(forKey: key)
                } else {
                    collapsedSections.insert(plugin.id)
                    UserDefaults.standard.set(true, forKey: key)
                }
            }
        }

        /// A plugin's header and, when expanded, its body. Global plugins can be pinned and moved
        /// from the header's context menu.
        private func pluginSection(_ plugin: AnyDebugDrawerPlugin, isGlobal: Bool) -> some View {
            let expanded = isExpanded(plugin)
            let pinned = layout.pinned.contains(plugin.id)

            return VStack(spacing: 0) {
                Button {
                    toggleExpanded(plugin)
                } label: {
                    PluginHeaderLabel(plugin: plugin, isExpanded: expanded, isPinned: pinned)
                }
                .buttonStyle(.plain)
                .accessibilityValue(expanded ? "Expanded" : "Collapsed")
                .accessibilityHint(isGlobal ? "Toggles the section. Its actions pin it or move it." : "Toggles the section.")
                .contextMenu {
                    if isGlobal {
                        Button(pinned ? "Unpin" : "Pin", systemImage: pinned ? "pin.slash" : "pin") {
                            updateLayout { $0.togglePin(plugin.id) }
                        }
                        Button("Move Up", systemImage: "arrow.up") {
                            updateLayout { $0.move(plugin.id, by: -1, among: drawer.globalPlugins) }
                        }
                        Button("Move Down", systemImage: "arrow.down") {
                            updateLayout { $0.move(plugin.id, by: 1, among: drawer.globalPlugins) }
                        }
                    }
                }

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
#endif
