#if DEBUG
    import SwiftUI

    /// Reads the model and hands its stores to `DatabaseBrowserView`, keeping what is selected,
    /// the search, the page and the query. It looks for stores again each time it appears, reads
    /// the selected table's page whenever the table, the page or the search changes, and runs
    /// the query on Run.
    struct DatabaseBrowserPluginView: View {
        @ObservedObject var model: DatabaseBrowserModel
        @State private var filter = ""
        @State private var selectedStore: DatabaseStore.ID?
        @State private var selectedTable: StoreTable.ID?
        @State private var search = ""
        @State private var pageIndex = 0
        @State private var page: Loadable<TablePage> = .loading
        @State private var sql = ""
        @State private var query: QueryState = .idle

        var body: some View {
            DatabaseBrowserView(
                stores: model.stores,
                filter: $filter,
                selectedStore: $selectedStore,
                selectedTable: $selectedTable,
                search: $search,
                page: page,
                sql: $sql,
                query: query,
                actions: DatabaseBrowserActions(
                    refresh: { Task { await model.refresh() } },
                    showPage: { pageIndex = $0 },
                    run: run
                )
            )
            .task { await model.refresh() }
            // Cancelled and started again on every change, so a read overtaken by a newer
            // request never lands.
            .task(id: pageRead) {
                guard let pageRead else { return }
                page = .loading
                let loaded = await model.page(pageRead.request, of: pageRead.store)
                if !Task.isCancelled {
                    page = loaded
                }
            }
            .onChange(of: selectedStore) {
                selectedTable = nil
                query = .idle
            }
            .onChange(of: selectedTable) {
                search = ""
                pageIndex = 0
                if let table = selectedTable, sql.isEmpty || sql.hasPrefix("SELECT * FROM ") {
                    sql = "SELECT * FROM \(table.quotedSQLIdentifier) LIMIT \(TablePageRequest.pageSize)"
                }
            }
            .onChange(of: search) {
                pageIndex = 0
            }
        }

        /// The selected store.
        private var store: DatabaseStore? {
            model.listings.first { $0.id == selectedStore }?.store
        }

        /// The page to read, while a table is selected.
        private var pageRead: PageRead? {
            guard let listing = model.listings.first(where: { $0.id == selectedStore }),
                  case let .success(schema) = listing.schema,
                  let table = schema.tables.first(where: { $0.id == selectedTable })
            else { return nil }
            return PageRead(store: listing.store, request: TablePageRequest(table: table, pageIndex: pageIndex, search: search))
        }

        private func run() {
            guard let store else { return }
            let sql = sql.straighteningQuotes
            query = .running
            Task {
                query = await model.run(sql, on: store)
            }
        }
    }

    /// A page to read, and the store it's read from.
    private struct PageRead: Hashable {
        let store: DatabaseStore
        let request: TablePageRequest
    }

    extension String {
        /// The text with curly quotes made straight, as SQL needs them: iOS's keyboard types
        /// ‘ ’ “ ” for ' and ".
        fileprivate var straighteningQuotes: String {
            String(map { character in
                switch character {
                case "‘", "’": "'"
                case "“", "”": "\""
                default: character
                }
            })
        }
    }
#endif
