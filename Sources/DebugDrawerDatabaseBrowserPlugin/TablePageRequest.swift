#if DEBUG
    import Foundation

    /// A page of a table's rows to read: which table, which page, and the text to search for.
    struct TablePageRequest: Hashable, Sendable {
        /// How many rows a page holds.
        static let pageSize = 50

        let table: StoreTable
        /// The page, from 0; a page past the last reads the last.
        let pageIndex: Int
        /// What the table's text columns must contain, ignoring ASCII case; blank for every row.
        let search: String

        init(table: StoreTable, pageIndex: Int = 0, search: String = "") {
            self.table = table
            self.pageIndex = pageIndex
            self.search = search
        }

        /// The search without surrounding whitespace.
        var trimmedSearch: String {
            search.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        /// The columns the search looks in; none when the search is blank.
        var searchedColumns: [String] {
            trimmedSearch.isEmpty ? [] : table.searchableColumns
        }

        /// The SQL that counts the rows the search matches.
        var countSQL: String {
            "SELECT count(*) FROM \(table.name.quotedSQLIdentifier)\(whereClause)"
        }

        /// The SQL that reads one page of them, its `LIMIT ? OFFSET ?` bound after the search's
        /// parameters, in `rowid` order where the table has one so pages don't overlap.
        var pageSQL: String {
            let order = table.hasRowID ? " ORDER BY rowid" : ""
            return "SELECT * FROM \(table.name.quotedSQLIdentifier)\(whereClause)\(order) LIMIT ? OFFSET ?"
        }

        /// The search's parameters: its pattern once per searched column.
        var searchParameters: [SQLiteParameter] {
            searchedColumns.map { _ in .text(trimmedSearch.containsLikePattern) }
        }

        /// The page to read, given how many rows match: `pageIndex` kept between the first page
        /// and the last.
        func clampedPageIndex(matching count: Int) -> Int {
            let lastPage = max(0, (count - 1) / Self.pageSize)
            return min(max(0, pageIndex), lastPage)
        }

        private var whereClause: String {
            let conditions = searchedColumns.map { "\($0.quotedSQLIdentifier) LIKE ? ESCAPE '\\'" }
            return conditions.isEmpty ? "" : " WHERE " + conditions.joined(separator: " OR ")
        }
    }
#endif
