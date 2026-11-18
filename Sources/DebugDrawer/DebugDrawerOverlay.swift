// watchOS shows the plugins as a navigation list instead (DrawerWatchList).
#if DEBUG && !os(watchOS)
    import SwiftUI

    // MARK: - Drawer panel view

    /// The drawer's panel and what slides it in and out. On the Mac and iOS it is the whole of the
    /// drawer's own window (DrawerChildPanel, DrawerSceneWindow); on tvOS an overlay on the app's
    /// window; on visionOS an ornament's content.
    struct DebugDrawerOverlay: View {
        @ObservedObject var drawer: DebugDrawer
        /// This window's drawer: open or closed, the outline or one plugin, regular or compact.
        @ObservedObject var presentation: DrawerPresentation
        /// Whether the panel is drawn: it follows `presentation.isOpen`, animated, and once it has
        /// gone the drawer's window is told so it can hide.
        @State var isShown: Bool
        /// Tracks which plugins the user has *collapsed*. Everything starts expanded.
        @State var collapsedSections: Set<String> = []
        /// What the search field holds; results show while it isn't empty.
        @State var query = ""
        /// The result Return runs, moved by the arrow keys.
        @State var highlighted = 0
        @FocusState var searchFocused: Bool
        /// The plugin header holding keyboard focus, moved by the next- and previous-plugin shortcuts.
        @FocusState var focusedPlugin: String?
        /// Pins, order and the last-used plugin, loaded once and saved on every change.
        @State var layout = DrawerLayout()
        /// The plugin at the top of the list: set to scroll there, and kept current as the user scrolls.
        @State var scrolledID: String?
        /// The last Create Report's progress or result, until dismissed.
        @State var reportState: DrawerReportResult.State?
        /// The navigator tab selected: all plugins, or one category's.
        @State var scope = DrawerScope.all
        /// The filter bar's toggles: stack traces without the system's frames, and only the
        /// plugins with something unread.
        @State var showsOnlyOwnCode = false
        @State var showsOnlyUnread = false
        @Environment(\.accessibilityReduceMotion) var reduceMotion

        init(drawer: DebugDrawer, presentation: DrawerPresentation) {
            self.drawer = drawer
            self.presentation = presentation
            _isShown = State(initialValue: presentation.isOpen)
        }

        var body: some View {
            #if os(visionOS)
                // An ornament beside the window (DebugDrawerModifier), sized by the modifier: the
                // panel alone, on glass, with no window edges or status bar to keep clear of.
                Group {
                    if presentation.isOpen {
                        panel
                            .frame(width: DrawerPanelLayout.regularWidth)
                            .glassBackgroundEffect()
                    }
                }
                .onAppear { loadCollapsedState() }
            #elseif os(macOS)
                // The panel fills a window of its own, which AppKit sizes and places
                // (DrawerChildPanel); it fades, since a slide would be clipped at the window's edge.
                Group {
                    if isShown {
                        panel
                            .drawerPanelSurface()
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { loadCollapsedState() }
                // `initial`: the window may first draw the panel after the drawer has opened (its
                // window was hidden until then), when there is no change left to see.
                .onChange(of: presentation.isOpen, initial: true) { _, isOpen in follow(isOpen: isOpen) }
            #else
                // The panel keeps inside the safe area, the keyboard's included, so it never slides
                // under the status bar and the filter bar at its foot stays above the keyboard.
                panelRow
                    .padding(.drawerPanel(layout: presentation.layout))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width + proxy.safeAreaInsets.leading + proxy.safeAreaInsets.trailing
                } action: { width in
                    let layout = DrawerPanelLayout(windowWidth: width)
                    if presentation.layout != layout { presentation.layout = layout }
                }
                .onAppear { loadCollapsedState() }
                // `initial`: the window may first draw the panel after the drawer has opened (its
                // window was hidden until then), when there is no change left to see.
                .onChange(of: presentation.isOpen, initial: true) { _, isOpen in follow(isOpen: isOpen) }
            #endif
        }

        #if !os(visionOS) && !os(macOS)
            var panelRow: some View {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)

                    if isShown {
                        Group {
                            switch presentation.layout {
                            case .regular: panel.frame(width: DrawerPanelLayout.regularWidth)
                            case .compact: panel.frame(maxWidth: .infinity)
                            }
                        }
                        .drawerPanelSurface()
                        // Where the panel is, for the window's hit testing: only the panel takes
                        // touches (DrawerSceneWindow).
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { presentation.panelFrame = $0 }
                        .onDisappear { presentation.panelFrame = nil }
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
        #endif

        /// Shows or hides the panel as the drawer opens or closes: slid or faded in, or at once
        /// when the system reduces motion. A compact panel opens at the list of plugins. Once
        /// the panel has gone, the drawer's window hides.
        func follow(isOpen: Bool) {
            guard isShown != isOpen else { return }
            if isOpen, presentation.layout == .compact, presentation.revealRequest == nil {
                presentation.navigation = .outline
            }
            let finished = { [presentation] in
                if !presentation.isOpen { presentation.host?.drawerDidHide() }
            }
            guard let animation = motion else {
                isShown = isOpen
                if !isOpen { finished() }
                return
            }
            withAnimation(animation) {
                isShown = isOpen
            } completion: {
                if !isOpen { finished() }
            }
        }

        /// The panel's slide, or none when the system reduces motion.
        var motion: Animation? {
            reduceMotion ? nil : .easeInOut(duration: 0.25)
        }

        /// The open drawer: the header block (title, jump bar, navigator tabs), the plugin outline
        /// or one plugin alone, and the filter bar at the foot.
        var panel: some View {
            VStack(spacing: 0) {
                DrawerHeader(
                    isReportInProgress: reportState?.isInProgress == true,
                    context: DrawerJumpBar.Context.current,
                    focus: shownAlone,
                    sections: sections,
                    navigate: navigate(to:),
                    createReport: createReport,
                    close: close
                )
                if shownAlone == nil {
                    DrawerNavigatorTabs(tabs: DrawerNavigatorTab.tabs(for: allPlugins, badges: drawer.badges), selection: $scope)
                        .padding(.vertical, 4)
                }
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
                Group {
                    if let plugin = shownAlone {
                        DrawerPluginDetail(plugin: plugin)
                            .environment(\.debugDrawerShowsOnlyOwnCode, showsOnlyOwnCode)
                    } else {
                        content
                    }
                }
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
                    close: backOrClose
                )
            }
            // A toast asks for its plugin; shown alone, or in the compact list, the drawer shows it
            // alone. The outline scrolls to it instead (content).
            .onAppear { revealAlone() }
            .onChange(of: presentation.revealRequest) { revealAlone() }
            #if os(tvOS)
                // The focus engine moves into the panel as one region, and the remote's Menu button
                // clears the search, then leaves a plugin shown alone, then closes the drawer, as
                // Escape does elsewhere. Both apply only while focus is in the open drawer, so
                // neither takes a button from the app (N2).
                .focusSection()
                .onExitCommand {
                    if query.isEmpty {
                        backOrClose()
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

        var allPlugins: [AnyDebugDrawerPlugin] {
            localPlugins + drawer.globalPlugins
        }

        /// The local plugins of this window's views, and those registered from no window.
        var localPlugins: [AnyDebugDrawerPlugin] {
            drawer.localPlugins(listedIn: presentation.scope)
        }

        /// The plugin shown alone, while it is still registered; `nil` in the outline.
        var shownAlone: AnyDebugDrawerPlugin? {
            presentation.navigation.pluginID.flatMap { id in allPlugins.first { $0.id == id } }
        }

        func loadCollapsedState() {
            for plugin in allPlugins where UserDefaults.standard.bool(forKey: plugin.collapsedStateKey) {
                collapsedSections.insert(plugin.id)
            }
            layout = DrawerLayout(from: .standard)
            // The list isn't on screen yet; it opens at this plugin.
            scrolledID = layout.lastUsed
        }

        /// Changes the layout and saves it.
        func updateLayout(_ change: (inout DrawerLayout) -> Void) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                change(&layout)
            }
            layout.save(to: .standard)
        }

        // MARK: - Navigation

        /// Shows the outline, or a plugin alone, which becomes the plugin the outline opens at.
        func navigate(to navigation: DrawerNavigation) {
            if let id = navigation.pluginID {
                updateLayout { $0.lastUsed = id }
            }
            presentation.navigation = navigation
            if navigation == .outline {
                // Back in the outline, the list opens at the plugin just shown.
                scrolledID = layout.lastUsed
            }
        }

        /// Escape and tvOS's Menu: from a plugin shown alone back to the outline, otherwise closed.
        func backOrClose() {
            if presentation.navigation == .outline {
                close()
            } else {
                navigate(to: .outline)
            }
        }

        /// Closes this window's drawer.
        func close() {
            presentation.isOpen = false
        }

        /// Shows the plugin a toast asked for alone, when the drawer already shows one alone or
        /// lists the plugins in the compact panel.
        func revealAlone() {
            guard let id = presentation.revealRequest,
                  presentation.navigation != .outline || presentation.layout == .compact
            else { return }
            presentation.revealRequest = nil
            guard allPlugins.contains(where: { $0.id == id }) else { return }
            navigate(to: .plugin(id))
        }

        // MARK: - Report

        /// Writes the report with the drawer and HUD hidden, so a screenshot in it shows the app
        /// rather than the drawer over it; the drawer reopens on the result.
        func createReport() {
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
        func sendReport(_ archive: URL, with uploader: any DebugDrawerReportUploader) {
            Task {
                await DrawerReportResult.State.send(archive, with: uploader) { reportState = $0 }
            }
        }
    }
#endif
