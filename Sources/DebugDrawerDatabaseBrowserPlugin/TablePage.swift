#if DEBUG
    import Foundation

    /// One page of a table's rows, and where it sits among the rows the search matches.
    struct TablePage: Hashable, Sendable {
        /// The page's rows.
        let rows: ResultSet
        /// Which page it is, from 0.
        let pageIndex: Int
        /// How many rows the search matches, on every page.
        let matchingCount: Int
        /// The columns the search looked in; empty when there was no search.
        let searchedColumns: [String]

        /// How many pages the matching rows fill; at least one.
        var pageCount: Int {
            max(1, (matchingCount + TablePageRequest.pageSize - 1) / TablePageRequest.pageSize)
        }

        var hasPreviousPage: Bool {
            pageIndex > 0
        }

        var hasNextPage: Bool {
            pageIndex + 1 < pageCount
        }

        /// Which rows the page shows, counting from 1: "Rows 51–100 of 312", "No rows".
        var rangeDescription: String {
            guard matchingCount > 0, !rows.rows.isEmpty else { return "No rows" }
            let first = pageIndex * TablePageRequest.pageSize + 1
            let last = first + rows.rows.count - 1
            return "Rows \(first.formatted())–\(last.formatted()) of \(matchingCount.formatted())"
        }
    }
#endif
