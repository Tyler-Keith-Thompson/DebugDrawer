#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The browser: the stores in a scrolling list under a filter field; below it, at the
    /// drawer's full width, the selected store's facts and tables, the selected table's rows and
    /// the query editor; then Refresh. With no stores it says where it looked.
    struct DatabaseBrowserView: View {
        let stores: StoresState
        /// What the filter field holds.
        @Binding var filter: String
        @Binding var selectedStore: DatabaseStore.ID?
        @Binding var selectedTable: StoreTable.ID?
        /// The selected table's search.
        @Binding var search: String
        /// The selected table's page.
        let page: Loadable<TablePage>
        /// What the query editor holds.
        @Binding var sql: String
        let query: QueryState
        let actions: DatabaseBrowserActions
        /// The tallest the store list grows before it scrolls.
        @ScaledMetric(relativeTo: .body) private var listHeight: CGFloat = 240

        var body: some View {
            switch stores {
            case .loading:
                DebugDrawerSection {
                    EmptyView()
                } footer: {
                    Text("Looking for stores…")
                }
            case let .loaded(listings) where listings.isEmpty:
                DebugDrawerSection {
                    EmptyView()
                } footer: {
                    Text("No stores found. The browser looks in Application Support, Documents and the app groups' containers "
                        + "for .sqlite, .sqlite3, .db and .store files.")
                }
                refresh
            case let .loaded(listings):
                list(listings)
            }
        }

        private func list(_ listings: [StoreListing]) -> some View {
            let matching = listings.filter { $0.matches(filter) }
            return VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSearchableList(
                    "Filter stores…",
                    text: $filter,
                    accessibilityLabel: "Filter stores by name, path, kind or table",
                    maxHeight: listHeight
                ) {
                    ForEach(matching) { listing in
                        StoreRow(listing: listing, isSelected: selectedStore == listing.id) {
                            selectedStore = selectedStore == listing.id ? nil : listing.id
                        }
                    }
                }
                if matching.isEmpty {
                    DebugDrawerSection {
                        EmptyView()
                    } footer: {
                        Text("No stores match “\(filter.trimmingCharacters(in: .whitespacesAndNewlines))”.")
                    }
                }
                // Below the list rather than inside it, so the tables and rows show at their
                // natural height instead of scrolling in a box that itself scrolls. Only while the
                // filter still lists the store.
                if let listing = matching.first(where: { $0.id == selectedStore }) {
                    StoreDetail(listing: listing, selectedTable: $selectedTable) { selectedStore = nil }
                    if case let .success(schema) = listing.schema {
                        if let table = schema.tables.first(where: { $0.id == selectedTable }) {
                            TableRowsSection(table: table, page: page, search: $search, onShowPage: actions.showPage)
                        }
                        QuerySection(sql: $sql, state: query, onRun: actions.run)
                    }
                }
                refresh
            }
        }

        private var refresh: some View {
            DebugDrawerActionRow {
                Button("Refresh", action: actions.refresh)
                    .accessibilityHint("Looks for stores again and reads their tables")
            }
        }
    }

    /// What the browser's buttons do.
    struct DatabaseBrowserActions {
        /// Looks for stores again.
        var refresh: () -> Void = {}
        /// Shows the selected table's page with this index, from 0.
        var showPage: (Int) -> Void = { _ in }
        /// Runs the query editor's SQL on the selected store.
        var run: () -> Void = {}
    }
#endif
