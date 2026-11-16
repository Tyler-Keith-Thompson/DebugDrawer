#if DEBUG
    import Foundation

    /// One thing the drawer's search field found: a plugin to jump to, or an action to run.
    enum DrawerSearchResult: Identifiable {
        case plugin(AnyDebugDrawerPlugin)
        case action(DebugDrawerAction, in: AnyDebugDrawerPlugin)

        var id: String {
            switch self {
            case let .plugin(plugin): "plugin:\(plugin.id)"
            case let .action(action, plugin): "action:\(plugin.id):\(action.id)"
            }
        }

        /// The plugins and actions in `plugins` that `query` matches, best first.
        ///
        /// A match is a case- and diacritic-insensitive substring of the title or, for an action, of
        /// a keyword. Titles that start with the query come first, then titles that contain it, then
        /// keyword matches; ties keep the order of `plugins` and, within a plugin, the plugin before
        /// its actions. A query of only whitespace matches nothing.
        ///
        /// - Complexity: O(*n* log *n*) in the number of plugins and actions.
        static func matches(_ query: String, in plugins: [AnyDebugDrawerPlugin]) -> [DrawerSearchResult] {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return [] }
            let candidates: [(rank: Rank, result: DrawerSearchResult)] = plugins.flatMap { plugin in
                let pluginMatch = Rank(title: plugin.title, keywords: [], term: term)
                    .map { [($0, DrawerSearchResult.plugin(plugin))] } ?? []
                let actionMatches = plugin.actions.compactMap { action in
                    Rank(title: action.title, keywords: action.keywords, term: term)
                        .map { ($0, DrawerSearchResult.action(action, in: plugin)) }
                }
                return pluginMatch + actionMatches
            }
            return candidates.enumerated()
                .sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }
                .map(\.element.result)
        }
    }

    extension DrawerSearchResult {
        /// How well a title or its keywords match, best first.
        fileprivate enum Rank: Int, Comparable {
            case titlePrefix, titleContains, keyword

            init?(title: String, keywords: [String], term: String) {
                let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
                if title.range(of: term, options: options.union(.anchored)) != nil {
                    self = .titlePrefix
                } else if title.range(of: term, options: options) != nil {
                    self = .titleContains
                } else if keywords.contains(where: { $0.range(of: term, options: options) != nil }) {
                    self = .keyword
                } else {
                    return nil
                }
            }

            static func < (lhs: Rank, rhs: Rank) -> Bool { lhs.rawValue < rhs.rawValue }
        }
    }

    extension DrawerSearchResult {
        /// The plugin's or the action's title.
        var title: String {
            switch self {
            case let .plugin(plugin): plugin.title
            case let .action(action, _): action.title
            }
        }

        /// The plugin's icon, or a bolt for an action.
        var icon: String {
            switch self {
            case let .plugin(plugin): plugin.icon
            case .action: "bolt"
            }
        }

        /// The plugin an action belongs to, shown under it; nil for a plugin.
        var pluginTitle: String? {
            switch self {
            case .plugin: nil
            case let .action(_, plugin): plugin.title
            }
        }
    }
#endif
