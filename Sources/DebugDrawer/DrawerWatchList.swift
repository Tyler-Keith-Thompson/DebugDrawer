#if DEBUG && os(watchOS)
    import SwiftUI

    // A watch screen has no room for a side panel of expanded sections, so the drawer takes the
    // compact navigation model instead. It keeps the stored layout's pinned plugins and order,
    // which the list only reads: pinning and moving belong to the bigger screens' context menus,
    // which watchOS deprecates. It drops collapsing (a row opens its plugin, so there is nothing
    // to collapse), search (dictating or scribbling a query costs more than scrolling a short list
    // with the Digital Crown), the keyboard shortcuts (no keyboard) and the bug-report button (no
    // shipped contributor builds for watchOS yet, and the overlay's hide-then-reopen would dismiss
    // and re-present this cover; createReport(in:) is still there for an app to call).

    /// The drawer on watchOS: a full-screen list of the plugins, grouped as the drawer groups them
    /// (Local, Pinned, then each category), where each row opens its plugin's view.
    struct DrawerWatchList: View {
        @ObservedObject var drawer: DebugDrawer
        /// The drawer's state, through which a toast asks for its plugin.
        @ObservedObject var presentation: DrawerPresentation
        /// The plugins opened from the list, by ID; a toast's plugin is pushed onto it.
        @State private var path: [String] = []
        /// Pins and order, loaded each time the drawer opens.
        @State private var layout = DrawerLayout()

        var body: some View {
            NavigationStack(path: $path) {
                DrawerWatchSections(
                    sections: layout.sections(local: drawer.localPlugins, global: drawer.globalPlugins),
                    badges: drawer.badges
                )
                .navigationTitle("Debug")
                .navigationDestination(for: String.self) { id in
                    if let plugin = (drawer.localPlugins + drawer.globalPlugins).first(where: { $0.id == id }) {
                        DrawerWatchPluginView(plugin: plugin)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close", systemImage: "xmark") { drawer.toggle() }
                            .accessibilityLabel("Close the debug drawer")
                    }
                }
            }
            .onAppear {
                layout = DrawerLayout(from: .standard)
                reveal()
            }
            .onChange(of: presentation.revealRequest) { reveal() }
        }

        /// Opens the plugin a toast asked for.
        private func reveal() {
            guard let id = presentation.revealRequest else { return }
            presentation.revealRequest = nil
            path = [id]
        }
    }

    /// The list of plugin rows, one section per group.
    struct DrawerWatchSections: View {
        let sections: [DrawerSection]
        /// Badge counts by plugin ID.
        let badges: [String: Int]

        var body: some View {
            List {
                if sections.isEmpty {
                    DrawerEmptyState()
                }
                ForEach(sections) { section in
                    Section(section.title) {
                        ForEach(section.plugins) { plugin in
                            NavigationLink(value: plugin.id) {
                                row(plugin, badge: badges[plugin.id])
                            }
                        }
                    }
                }
            }
        }

        /// A plugin's icon and title, and its badge count, if it has one (watchOS has no list
        /// badges, so the count is drawn beside the title).
        private func row(_ plugin: AnyDebugDrawerPlugin, badge: Int?) -> some View {
            HStack {
                Label(plugin.title, systemImage: plugin.icon)
                Spacer()
                if let badge {
                    Text(badge, format: .number)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(badge.map { "\($0) new" } ?? "")
        }
    }

    /// One plugin's view, scrolled with the Digital Crown, under the plugin's title.
    struct DrawerWatchPluginView: View {
        let plugin: AnyDebugDrawerPlugin

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    plugin.body
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                // The system's margins keep the rows off the screen's rounded corners.
                .scenePadding(.horizontal)
            }
            .navigationTitle(plugin.title)
        }
    }
#endif
