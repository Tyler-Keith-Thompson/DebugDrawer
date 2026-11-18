// watchOS shows the plugins as a navigation list instead (DrawerWatchList).
#if DEBUG && !os(watchOS)
    import SwiftUI

    // MARK: - Search

    extension DebugDrawerOverlay {
        var searchField: some View {
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

        var searchResults: some View {
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

        func moveHighlight(by step: Int) -> KeyPress.Result {
            let count = DrawerSearchResult.matches(query, in: allPlugins).count
            guard count > 0 else { return .ignored }
            highlighted = min(max(highlighted + step, 0), count - 1)
            return .handled
        }

        func chooseHighlighted() {
            let found = DrawerSearchResult.matches(query, in: allPlugins)
            guard found.indices.contains(highlighted) else { return }
            choose(found[highlighted])
        }

        /// Shows a plugin, or runs an action, and clears the search. A plugin opens alone while
        /// the drawer shows one alone or is compact; in the outline it is expanded and scrolled to.
        func choose(_ result: DrawerSearchResult) {
            query = ""
            searchFocused = false
            switch result {
            case let .plugin(plugin):
                if presentation.navigation != .outline || presentation.layout == .compact {
                    navigate(to: .plugin(plugin.id))
                    return
                }
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
