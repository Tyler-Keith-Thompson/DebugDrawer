#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The selected table's rows: a search field over its text columns, which rows the page shows,
    /// the page in a grid, then Previous, Next and Copy Page as CSV. A failed read shows as an
    /// issue row.
    struct TableRowsSection: View {
        let table: StoreTable
        let page: Loadable<TablePage>
        @Binding var search: String
        /// Shows the page with this index, from 0.
        let onShowPage: (Int) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection("Rows of \(table.displayName)") {
                    TextField("Search text columns…", text: $search)
                        .debugDrawerTextFieldStyle()
                        .disabled(table.searchableColumns.isEmpty)
                        .accessibilityLabel("Search the text columns of \(table.displayName)")
                    content
                } footer: {
                    Text(searchNote)
                }
                if case let .loaded(page) = page {
                    DebugDrawerActionRow {
                        Button("Previous") { onShowPage(page.pageIndex - 1) }
                            .disabled(!page.hasPreviousPage)
                            .accessibilityHint("Shows the previous \(TablePageRequest.pageSize) rows")
                        Button("Next") { onShowPage(page.pageIndex + 1) }
                            .disabled(!page.hasNextPage)
                            .accessibilityHint("Shows the next \(TablePageRequest.pageSize) rows")
                        DebugDrawerCopyButton("Copy Page as CSV") { page.rows.csv }
                    }
                }
            }
        }

        @ViewBuilder private var content: some View {
            switch page {
            case .loading:
                Text("Reading…")
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.secondary)
                    .debugDrawerRowPadding()
            case let .failed(error):
                DebugDrawerIssueRow(error.title, severity: .error) {
                    Text(error.explanation)
                }
            case let .loaded(page):
                Text(page.rangeDescription)
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.secondary)
                    .debugDrawerRowPadding()
                ResultGrid(result: page.rows)
            }
        }

        /// Which columns the search looks in, or that there are none.
        private var searchNote: String {
            let columns = table.searchableColumns
            guard !columns.isEmpty else { return "The table has no text columns to search." }
            return "Search looks in \(columns.formatted(.list(type: .and))), ignoring the case of ASCII letters."
        }
    }
#endif
