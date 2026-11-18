// watchOS shows the plugins as a navigation list instead (DrawerWatchList).
#if DEBUG && !os(watchOS)
    import SwiftUI

    // MARK: - Plugin outline

    extension DebugDrawerOverlay {
        var content: some View {
            ScrollViewReader { proxy in
                pluginList
                    // A toast opens the drawer and asks for its plugin in the same turn; the list can
                    // scroll only once it is on screen, and while it is open a request scrolls at once.
                    // The proxy scrolls even when scrolledID already names the plugin.
                    .onAppear { reveal(using: proxy) }
                    .onChange(of: presentation.revealRequest) { reveal(using: proxy) }
            }
        }

        var pluginList: some View {
            ScrollView {
                if !drawer.hasPlugins {
                    DrawerEmptyState()
                } else {
                    // Local plugins first (contextual tools take precedence), then the global ones:
                    // pinned first, then by category. The navigator tabs name the categories, so
                    // the outline has no group headings.
                    LazyVStack(spacing: 0) {
                        ForEach(listedSections) { section in
                            ForEach(section.plugins) { plugin in
                                pluginSection(plugin, isGlobal: section.kind != .local)
                            }
                        }
                        if listedSections.isEmpty {
                            Text(showsOnlyUnread ? "Nothing unread" : "No plugins")
                                .debugDrawerFont(.secondary)
                                .foregroundStyle(DrawerPalette.secondaryText)
                                .padding()
                        }
                    }
                    .scrollTargetLayout()
                    .environment(\.debugDrawerShowsOnlyOwnCode, showsOnlyOwnCode)
                }
            }
            .scrollPosition(id: $scrolledID, anchor: .top)
            .onChange(of: scrolledID) {
                guard let scrolledID, scrolledID != layout.lastUsed else { return }
                layout.lastUsed = scrolledID
                layout.save(to: .standard)
            }
        }

        var sections: [DrawerSection] {
            layout.sections(local: drawer.localPlugins, global: drawer.globalPlugins)
        }

        /// The sections as the outline lists them: the selected tab's, and only plugins with
        /// something unread while that toggle is on.
        var listedSections: [DrawerSection] {
            scope.filter(sections, unread: showsOnlyUnread ? Set(drawer.badges.keys) : nil)
        }

        /// The plugins in the order the list shows them.
        var listedPluginIDs: [String] {
            listedSections.flatMap { $0.plugins.map(\.id) }
        }

        /// Moves to the plugin `step` places from the current one: shown alone, the next plugin
        /// alone; in the outline, scrolled to the top, with keyboard focus on its header where the
        /// system lets buttons take focus.
        func showPlugin(by step: Int) {
            if let current = presentation.navigation.pluginID {
                let order = sections.flatMap { $0.plugins.map(\.id) }
                guard let target = DrawerKeyboardShortcuts.plugin(by: step, from: current, in: order) else { return }
                navigate(to: .plugin(target))
                return
            }
            guard let target = DrawerKeyboardShortcuts.plugin(by: step, from: scrolledID, in: listedPluginIDs) else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                scrolledID = target
            }
            focusedPlugin = target
        }

        func isExpanded(_ plugin: AnyDebugDrawerPlugin) -> Bool {
            !collapsedSections.contains(plugin.id)
        }

        /// Expands the plugin a toast asked for and scrolls the list to it.
        func reveal(using proxy: ScrollViewProxy) {
            guard let id = presentation.revealRequest, presentation.layout == .regular else { return }
            presentation.revealRequest = nil
            guard let plugin = allPlugins.first(where: { $0.id == id }) else { return }
            expand(plugin)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .top)
            }
        }

        /// Opens the plugin, first widening the outline to every plugin if a tab or toggle hides it.
        func expand(_ plugin: AnyDebugDrawerPlugin) {
            if !listedPluginIDs.contains(plugin.id) {
                scope = .all
                showsOnlyUnread = false
            }
            guard collapsedSections.contains(plugin.id) else { return }
            toggleExpanded(plugin)
        }

        func toggleExpanded(_ plugin: AnyDebugDrawerPlugin) {
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

        /// A plugin's header and, when expanded, its body, with a button that shows it alone.
        /// Global plugins can be pinned and moved from the header's context menu. In the compact
        /// panel the header is a row of a list: it shows the plugin alone, and no body opens under it.
        func pluginSection(_ plugin: AnyDebugDrawerPlugin, isGlobal: Bool) -> some View {
            let compact = presentation.layout == .compact
            let expanded = !compact && isExpanded(plugin)
            let pinned = layout.pinned.contains(plugin.id)

            return DrawerPluginSection(
                plugin: plugin,
                isExpanded: expanded,
                showAlone: compact ? nil : { navigate(to: .plugin(plugin.id)) }
            ) {
                PluginSectionHeader(
                    plugin: plugin,
                    isExpanded: expanded,
                    isPinned: pinned,
                    badge: drawer.badges[plugin.id],
                    isMovable: isGlobal,
                    opensAlone: compact
                ) {
                    if compact {
                        navigate(to: .plugin(plugin.id))
                    } else {
                        toggleExpanded(plugin)
                    }
                }
                .focused($focusedPlugin, equals: plugin.id)
                .contextMenu { pluginMenu(plugin, isGlobal: isGlobal, pinned: pinned) }
            }
            .id(plugin.id)
        }

        /// The header's context menu: show the plugin alone, pin and move a global plugin, and
        /// show it in the HUD.
        @ViewBuilder
        func pluginMenu(_ plugin: AnyDebugDrawerPlugin, isGlobal: Bool, pinned: Bool) -> some View {
            Button("Show Alone", systemImage: "chevron.forward") {
                navigate(to: .plugin(plugin.id))
            }
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
            if plugin.hasHUD {
                let inHUD = drawer.hudLayout.pinned.contains(plugin.id)
                Button(inHUD ? "Remove from HUD" : "Show in HUD", systemImage: inHUD ? "rectangle.slash" : "rectangle.inset.topleft.filled") {
                    drawer.toggleHUD(forPlugin: plugin.id)
                }
            }
        }
    }
#endif
