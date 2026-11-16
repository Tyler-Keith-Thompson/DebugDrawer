#if DEBUG
    import Foundation

    /// How the user arranged the drawer's global plugins: which are pinned, their order, and the
    /// plugin they used last. Persisted per app in `UserDefaults`, beside each plugin's collapsed
    /// state.
    struct DrawerLayout: Codable, Equatable {
        /// Pinned plugin IDs, in the order they show at the top.
        var pinned: [String] = []
        /// Global plugin IDs in the user's order; plugins not listed follow in registration order.
        var order: [String] = []
        /// The plugin the drawer scrolls to when it opens.
        var lastUsed: String?

        /// The key the layout is stored under.
        static let defaultsKey = "com.debugdrawer.layout"

        init() {}

        /// The layout stored in `defaults`, or an empty one if none is stored or it can't be read.
        init(from defaults: UserDefaults) {
            guard let data = defaults.data(forKey: Self.defaultsKey),
                  let stored = try? JSONDecoder().decode(DrawerLayout.self, from: data)
            else { return }
            self = stored
        }

        /// Stores the layout in `defaults`.
        func save(to defaults: UserDefaults) {
            // Encoding three plain fields can't fail; a layout that isn't saved only costs the arrangement.
            guard let data = try? JSONEncoder().encode(self) else { return }
            defaults.set(data, forKey: Self.defaultsKey)
        }

        /// `plugins` grouped for display: the pinned ones first, then one group per category,
        /// alphabetically, with the default category (`General`) last.
        ///
        /// - Complexity: O(*n* log *n*) in the number of plugins.
        func sections(for plugins: [AnyDebugDrawerPlugin]) -> [DrawerSection] {
            let pinnedPlugins = pinned.compactMap { id in plugins.first { $0.id == id } }
            let unpinned = plugins.enumerated()
                .filter { !pinned.contains($0.element.id) }
                .sorted { rank(of: $0.element.id, registered: $0.offset) < rank(of: $1.element.id, registered: $1.offset) }
                .map(\.element)
            let categories = Set(unpinned.map(\.category)).sorted(by: DrawerSection.categoryPrecedes)
            let grouped = categories.map { category in
                DrawerSection(kind: .category, title: category, plugins: unpinned.filter { $0.category == category })
            }
            let pinnedSection = pinnedPlugins.isEmpty
                ? []
                : [DrawerSection(kind: .pinned, title: "Pinned", plugins: pinnedPlugins)]
            return pinnedSection + grouped
        }

        /// Every plugin the drawer lists, grouped as it shows them: the `local` plugins first, in
        /// their order, under Local, then the `global` ones as ``sections(for:)`` groups them.
        ///
        /// - Complexity: O(*n* log *n*) in the number of plugins.
        func sections(local: [AnyDebugDrawerPlugin], global: [AnyDebugDrawerPlugin]) -> [DrawerSection] {
            let localSection = local.isEmpty ? [] : [DrawerSection(kind: .local, title: "Local", plugins: local)]
            return localSection + sections(for: global)
        }

        /// Pins the plugin at the end of the pinned group, or unpins it.
        mutating func togglePin(_ id: String) {
            if let index = pinned.firstIndex(of: id) {
                pinned.remove(at: index)
            } else {
                pinned.append(id)
            }
        }

        /// Moves the plugin `offset` places within its group (negative moves it up), stopping at
        /// the group's ends.
        mutating func move(_ id: String, by offset: Int, among plugins: [AnyDebugDrawerPlugin]) {
            let sections = sections(for: plugins)
            guard let section = sections.first(where: { $0.plugins.contains { $0.id == id } }) else { return }
            var ids = section.plugins.map(\.id)
            // The guard above found the plugin in this section, so it has an index.
            let from = ids.firstIndex(of: id)!
            let to = min(max(from + offset, 0), ids.count - 1)
            guard from != to else { return }
            ids.insert(ids.remove(at: from), at: to)
            if section.kind == .pinned {
                pinned = ids
            } else {
                order = sections.filter { $0.kind == .category }
                    .flatMap { $0.id == section.id ? ids : $0.plugins.map(\.id) }
            }
        }
    }

    /// One group of the drawer's plugins.
    struct DrawerSection: Identifiable {
        /// What groups the plugins.
        enum Kind: Equatable {
            /// The local plugins, registered by the views on screen.
            case local
            /// The global plugins the user pinned.
            case pinned
            /// The unpinned global plugins of one category, the section's title.
            case category
        }

        let kind: Kind
        let title: String
        let plugins: [AnyDebugDrawerPlugin]

        // A category may be titled "Pinned" or "Local" too.
        var id: String {
            switch kind {
            case .local: "local"
            case .pinned: "pinned"
            case .category: "category:\(title)"
            }
        }
    }

    extension DrawerLayout {
        /// Where a plugin sorts: its place in `order`, or after every ordered plugin by registration.
        fileprivate func rank(of id: String, registered: Int) -> Int {
            order.firstIndex(of: id) ?? order.count + registered
        }
    }

    extension DrawerSection {
        /// Categories sort alphabetically, with the default category last.
        fileprivate static func categoryPrecedes(_ lhs: String, _ rhs: String) -> Bool {
            let fallback = defaultPluginCategory
            if (lhs == fallback) != (rhs == fallback) { return rhs == fallback }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
    }
#endif
