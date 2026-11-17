#if DEBUG
    import DebugDrawer
    import Foundation

    extension DatabaseBrowserPlugin: DebugDrawerReportContributor {
        /// Adds `databases.txt`: the stores found, with their tables and row counts, as last read.
        public func contribute(to report: inout DebugDrawerReport, redaction _: DebugDrawerRedaction) {
            Self.contribute(model.stores, to: &report)
        }

        /// Adds the stores as `databases.txt`. No row is read into it, since rows may hold what a
        /// report shouldn't carry; table names and counts describe the app's own schema.
        static func contribute(_ stores: StoresState, to report: inout DebugDrawerReport) {
            report.add(text: text(stores), named: "databases.txt")
        }

        static func text(_ stores: StoresState) -> String {
            guard case let .loaded(listings) = stores else { return "Stores: not read yet" }
            return (["Stores (\(listings.count)):"] + listings.flatMap(\.reportLines)).joined(separator: "\n")
        }
    }

    extension StoreListing {
        /// Its path, what it is, then each table with its row count, indented.
        fileprivate var reportLines: [String] {
            let wal = store.walSize.map { ", WAL file \($0.formatted(.byteCount(style: .file)))" } ?? ""
            let header = [
                "  \(store.path)",
                "    folder: \(store.location.title)",
                "    size: \(store.size.formatted(.byteCount(style: .file)))\(wal)",
                "    journal: \(store.journalMode.title)"
            ]
            switch schema {
            case let .failure(error):
                return header + ["    can't be read: \(error.title)"]
            case let .success(schema):
                return header + ["    kind: \(schema.kind.title)", "    tables (\(schema.tables.count)):"] + schema.tables.map(\.reportLine)
            }
        }
    }

    extension StoreTable {
        /// `ZORDER (Order): 312 rows`, or `name: count failed`.
        fileprivate var reportLine: String {
            let entity = entity.map { " (\($0.name))" } ?? ""
            let view = isView ? " (view)" : ""
            let count = rowCount.map { $0 == 1 ? "1 row" : "\($0) rows" } ?? "count failed"
            return "      \(name)\(entity)\(view): \(count)"
        }
    }
#else
    import DebugDrawer

    // The release stand-in: release builds make no reports.
    extension DatabaseBrowserPlugin: DebugDrawerReportContributor {
        /// Adds nothing: release builds make no reports.
        public func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {}
    }
#endif
