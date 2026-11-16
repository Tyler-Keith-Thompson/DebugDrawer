// watchOS shows the plugins as a navigation list instead (DrawerWatchList).
#if DEBUG && !os(watchOS)
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
        /// The plugin header holding keyboard focus, moved by the next- and previous-plugin shortcuts.
        @FocusState private var focusedPlugin: String?
        /// Pins, order and the last-used plugin, loaded once and saved on every change.
        @State private var layout = DrawerLayout()
        /// The plugin at the top of the list: set to scroll there, and kept current as the user scrolls.
        @State private var scrolledID: String?
        /// The last Create Report's progress or result, until dismissed.
        @State private var reportState: DrawerReportResult.State?
        /// The navigator tab selected: all plugins, or one category's.
        @State private var scope = DrawerScope.all
        /// The filter bar's toggles: stack traces without the system's frames, and only the
        /// plugins with something unread.
        @State private var showsOnlyOwnCode = false
        @State private var showsOnlyUnread = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private let drawerWidth: CGFloat = 340 * .debugDrawerTextScale

        var body: some View {
            #if os(visionOS)
                // An ornament beside the window (DebugDrawerModifier), sized by the modifier: the
                // panel alone, on glass, with no window edges or status bar to keep clear of.
                Group {
                    if drawer.isOpen {
                        panel
                            .frame(width: drawerWidth)
                            .glassBackgroundEffect()
                    }
                }
                .onAppear { loadCollapsedState() }
            #else
                // The reader respects the safe area so its proxy reports the window's insets; the panel
                // inside it ignores the safe area and pads by them, so it reaches the window's edges
                // without sliding under the status bar.
                GeometryReader { geometry in
                    panelRow
                        .padding(.drawerPanel(safeArea: geometry.safeAreaInsets))
                        .ignoresSafeArea()
                }
                .onAppear { loadCollapsedState() }
            #endif
        }

        private var panelRow: some View {
            HStack(spacing: 0) {
                Spacer()

                if drawer.isOpen {
                    panel
                        .frame(width: drawerWidth)
                        .drawerPanelSurface()
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
        }

        /// The open drawer: the header block (title, jump bar, navigator tabs), the plugin outline,
        /// and the filter bar at the foot.
        private var panel: some View {
            VStack(spacing: 0) {
                DrawerHeader(
                    isReportInProgress: reportState?.isInProgress == true,
                    context: DrawerJumpBar.Context.current,
                    createReport: createReport,
                    close: { drawer.toggle() }
                )
                DrawerNavigatorTabs(tabs: DrawerNavigatorTab.tabs(for: allPlugins, badges: drawer.badges), selection: $scope)
                .padding(.vertical, 4)
                DrawerRule()
                if let reportState {
                    DrawerReportResult(
                        state: reportState,
                        send: drawer.reportUploader.map { uploader in { sendReport($0, with: uploader) } },
                        dismiss: { self.reportState = nil }
                    )
                }
                if !query.isEmpty {
                    searchResults
                }
                content
                    .frame(maxHeight: .infinity, alignment: .top)
                DrawerFilterBar(field: { searchField }, showsOnlyOwnCode: $showsOnlyOwnCode, showsOnlyUnread: $showsOnlyUnread)
            }
            // The shortcuts exist only inside the open drawer, so none of them opens it (N2).
            .background {
                DrawerKeyboardShortcuts(
                    closesOnEscape: query.isEmpty,
                    search: { searchFocused = true },
                    nextPlugin: { showPlugin(by: 1) },
                    previousPlugin: { showPlugin(by: -1) },
                    close: { drawer.toggle() }
                )
            }
            #if os(tvOS)
                // The focus engine moves into the panel as one region, and the remote's Menu button
                // clears the search, then closes the drawer, as Escape does elsewhere. Both apply only
                // while focus is in the open drawer, so neither takes a button from the app (N2).
                .focusSection()
                .onExitCommand {
                    if query.isEmpty {
                        drawer.toggle()
                    } else {
                        query = ""
                    }
                }
                // Opened from the app, focus would stay on the app's control behind the panel, so
                // it moves to the plugin the list opens at (the last one used), or the first.
                .defaultFocus($focusedPlugin, scrolledID ?? listedPluginIDs.first)
                .onAppear { focusedPlugin = scrolledID ?? listedPluginIDs.first }
            #endif
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

        // MARK: - Report

        /// Writes the report with the drawer and HUD hidden, so a screenshot in it shows the app
        /// rather than the drawer over it; the drawer reopens on the result.
        private func createReport() {
            reportState = .creating
            drawer.performWhileHidden {
                do {
                    reportState = try .ready(drawer.createReport())
                } catch {
                    reportState = .failed("The report couldn't be written.")
                }
            }
        }

        /// Sends the zip with the app's uploader, showing its progress and outcome; Retry calls
        /// this again with the same zip.
        private func sendReport(_ archive: URL, with uploader: any DebugDrawerReportUploader) {
            Task {
                await DrawerReportResult.State.send(archive, with: uploader) { reportState = $0 }
            }
        }

        // MARK: - Plugin list

        private var content: some View {
            ScrollViewReader { proxy in
                pluginList
                    // A toast opens the drawer and asks for its plugin in the same turn; the list can
                    // scroll only once it is on screen, and while it is open a request scrolls at once.
                    // The proxy scrolls even when scrolledID already names the plugin.
                    .onAppear { reveal(using: proxy) }
                    .onChange(of: drawer.revealRequest) { reveal(using: proxy) }
            }
        }

        private var pluginList: some View {
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

        private var sections: [DrawerSection] {
            layout.sections(local: drawer.localPlugins, global: drawer.globalPlugins)
        }

        /// The sections as the outline lists them: the selected tab's, and only plugins with
        /// something unread while that toggle is on.
        private var listedSections: [DrawerSection] {
            scope.filter(sections, unread: showsOnlyUnread ? Set(drawer.badges.keys) : nil)
        }

        /// The plugins in the order the list shows them.
        private var listedPluginIDs: [String] {
            listedSections.flatMap { $0.plugins.map(\.id) }
        }

        /// Scrolls the list to the plugin `step` places from the one at its top, and moves keyboard
        /// focus to its header where the system lets buttons take focus.
        private func showPlugin(by step: Int) {
            guard let target = DrawerKeyboardShortcuts.plugin(by: step, from: scrolledID, in: listedPluginIDs) else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                scrolledID = target
            }
            focusedPlugin = target
        }

        private func isExpanded(_ plugin: AnyDebugDrawerPlugin) -> Bool {
            !collapsedSections.contains(plugin.id)
        }

        /// Expands the plugin a toast asked for and scrolls the list to it.
        private func reveal(using proxy: ScrollViewProxy) {
            guard let id = drawer.revealRequest else { return }
            drawer.revealRequest = nil
            guard let plugin = allPlugins.first(where: { $0.id == id }) else { return }
            expand(plugin)
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                proxy.scrollTo(id, anchor: .top)
            }
        }

        /// Opens the plugin, first widening the outline to every plugin if a tab or toggle hides it.
        private func expand(_ plugin: AnyDebugDrawerPlugin) {
            if !listedPluginIDs.contains(plugin.id) {
                scope = .all
                showsOnlyUnread = false
            }
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

            return DrawerPluginSection(plugin: plugin, isExpanded: expanded) {
                PluginSectionHeader(
                    plugin: plugin,
                    isExpanded: expanded,
                    isPinned: pinned,
                    badge: drawer.badges[plugin.id],
                    isMovable: isGlobal
                ) {
                    toggleExpanded(plugin)
                }
                .focused($focusedPlugin, equals: plugin.id)
                .contextMenu { pluginMenu(plugin, isGlobal: isGlobal, pinned: pinned) }
            }
            .id(plugin.id)
        }

        /// The header's context menu: pin and move a global plugin, and show it in the HUD.
        @ViewBuilder
        private func pluginMenu(_ plugin: AnyDebugDrawerPlugin, isGlobal: Bool, pinned: Bool) -> some View {
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

    // MARK: - Search

    extension DebugDrawerOverlay {
        private var searchField: some View {
            DrawerSearchField(query: $query)
                .focused($searchFocused)
                .onChange(of: query) { highlighted = 0 }
                .onSubmit { chooseHighlighted() }
            // On tvOS the arrows are how focus leaves the field, to the results (buttons the focus
            // engine reaches) and the plugins, and Menu clears the search (onExitCommand above).
            #if !os(tvOS)
                .onKeyPress(.downArrow) { moveHighlight(by: 1) }
                .onKeyPress(.upArrow) { moveHighlight(by: -1) }
                .onKeyPress(.escape) {
                    guard !query.isEmpty else { return .ignored }
                    query = ""
                    return .handled
                }
            #endif
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
    }
#endif
