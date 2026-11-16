// watchOS shows the plugins as a navigation list instead (DrawerWatchList).
#if DEBUG && !os(watchOS)
    import SwiftUI

    /// Which plugins the drawer lists: all of them, or one category's.
    enum DrawerScope: Hashable {
        case all
        case category(String)

        /// `sections` as the outline lists them under this scope: only this category's plugins
        /// and, when `unread` isn't `nil`, only the plugins it names. Sections left empty are
        /// dropped.
        func filter(_ sections: [DrawerSection], unread: Set<String>?) -> [DrawerSection] {
            sections.compactMap { section in
                let plugins = section.plugins.filter { plugin in
                    let inScope = switch self {
                    case .all: true
                    case let .category(category): plugin.category == category
                    }
                    return inScope && (unread?.contains(plugin.id) ?? true)
                }
                return plugins.isEmpty ? nil : DrawerSection(kind: section.kind, title: section.title, plugins: plugins)
            }
        }
    }

    /// One of the navigator's tabs: the scope it selects, its name and symbol, and whether any of
    /// its plugins has something unread.
    struct DrawerNavigatorTab: Identifiable, Equatable {
        let scope: DrawerScope
        let title: String
        let systemImage: String
        let hasUnread: Bool

        var id: DrawerScope { scope }

        /// All, then a tab per category of `plugins` in the drawer's order, each marked unread
        /// when one of its plugins has a badge in `badges`.
        ///
        /// - Complexity: O(*n* log *n*) in the number of plugins.
        static func tabs(for plugins: [AnyDebugDrawerPlugin], badges: [String: Int]) -> [DrawerNavigatorTab] {
            let unread = Set(plugins.filter { badges[$0.id] != nil }.map(\.category))
            let categories = Set(plugins.map(\.category)).sorted(by: DrawerSection.categoryPrecedes)
            let all = DrawerNavigatorTab(scope: .all, title: "All", systemImage: "square.grid.2x2", hasUnread: !unread.isEmpty)
            return [all] + categories.map { category in
                DrawerNavigatorTab(
                    scope: .category(category),
                    title: category,
                    systemImage: symbol(for: category, plugins: plugins),
                    hasUnread: unread.contains(category)
                )
            }
        }

        /// The symbol of a category the drawer's plugins ship with, or else the first of its
        /// plugins' icons.
        private static func symbol(for category: String, plugins: [AnyDebugDrawerPlugin]) -> String {
            switch category {
            case "App": "app.badge"
            case "Interface": "rectangle.3.group"
            case "Logs & Network": "network"
            case "Performance": "gauge.with.dots.needle.67percent"
            case "Storage": "externaldrive"
            case defaultPluginCategory: "puzzlepiece.extension"
            default: plugins.first { $0.category == category }?.icon ?? "puzzlepiece.extension"
            }
        }
    }

    /// The navigator's tab bar, as Xcode's navigator selector: icon-only square tabs (24 points on
    /// the Mac, 44 on iOS) spaced evenly across the panel, the selected one's square on the soft
    /// selection with its symbol in the accent color, the
    /// others in the secondary color, and a red dot on a tab with something unread. Each tab reads
    /// to VoiceOver as a tab named for its category.
    struct DrawerNavigatorTabs: View {
        let tabs: [DrawerNavigatorTab]
        @Binding var selection: DrawerScope
        @ScaledMetric(relativeTo: .body) private var height = DrawerSpacing.tabHeight
        @ScaledMetric(relativeTo: .body) private var dot = DrawerSpacing.unreadDot
        @ScaledMetric(relativeTo: .body) private var inset = DrawerSpacing.panelInset

        var body: some View {
            HStack(spacing: 2) {
                ForEach(tabs) { tab in
                    Button {
                        selection = tab.scope
                    } label: {
                        label(for: tab)
                    }
                    .debugDrawerButtonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityValue(tab.hasUnread ? "Unread" : "")
                    .accessibilityAddTraits(tab.scope == selection ? .isSelected : [])
                    .help(tab.title)
                    // Each square centered in an equal share of the width spaces the tabs evenly.
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, inset)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isTabBar)
        }

        private func label(for tab: DrawerNavigatorTab) -> some View {
            let isSelected = tab.scope == selection
            return Image(systemName: tab.systemImage)
                .accessibilityLabel(tab.title)
                .debugDrawerFont(.body)
                .foregroundStyle(isSelected ? DrawerPalette.accent : DrawerPalette.secondaryText)
                .overlay(alignment: .topTrailing) {
                    if tab.hasUnread {
                        Circle()
                            .fill(DrawerPalette.error)
                            .frame(width: dot, height: dot)
                            .padding(DrawerSpacing.unreadRing)
                            .background(Circle().fill(isSelected ? DrawerPalette.softSelection : DrawerPalette.panel))
                            .offset(x: dot * 0.6, y: -dot * 0.4)
                    }
                }
                // A square of its own, as Xcode's navigator selector draws one, so the selection is
                // the tab's square rather than its share of the panel's width.
                .frame(width: height, height: height)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: DrawerSpacing.tabRadius).fill(DrawerPalette.softSelection)
                    }
                }
                .contentShape(Rectangle())
        }
    }
#endif
