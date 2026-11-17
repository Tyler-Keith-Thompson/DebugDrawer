#if DEBUG
    import Foundation

    extension SQLiteValue {
        /// The value as a cell shows it: `NULL`; an integer in full; a real to 15 significant
        /// digits, as SQLite's own `printf('%!.15g')` gives it, so `32.480000000000004` reads
        /// `32.48`; text as it is; a blob as its size, then its first bytes in hex
        /// (`4 bytes · 89 50 4E 47`), with an ellipsis when there are more.
        var displayText: String {
            switch self {
            case .null: "NULL"
            case let .integer(value): String(value)
            case let .real(value): Self.realText(value)
            case let .text(value): value
            case let .blob(size, prefix): Self.blobSummary(size: size, prefix: prefix)
            }
        }

        /// What a cell shows on its one line: ``displayText`` up to its first line break, cut to
        /// `limit` characters with an ellipsis. Cells are monospaced, so a character count is a
        /// width.
        func cellText(limit: Int) -> String {
            let line = displayText.prefix { !$0.isNewline }
            let isCut = line.count > limit || line.endIndex != displayText.endIndex
            return isCut ? String(line.prefix(limit)) + "…" : String(line)
        }

        /// Whether a cell shows only part of ``displayText``.
        func isCut(at limit: Int) -> Bool {
            cellText(limit: limit) != displayText
        }

        /// The storage class's name, as `typeof()` gives it.
        var typeName: String {
            switch self {
            case .null: "null"
            case .integer: "integer"
            case .real: "real"
            case .text: "text"
            case .blob: "blob"
            }
        }

        private static func realText(_ value: Double) -> String {
            guard value.isFinite else { return String(value) }
            let text = String(format: "%.15g", value)
            // A whole real keeps its point, so it reads apart from an integer, as SQLite shows it.
            return text.contains { $0 == "." || $0 == "e" } ? text : text + ".0"
        }

        private static func blobSummary(size: Int, prefix: Data) -> String {
            let count = size == 1 ? "1 byte" : "\(size.formatted()) bytes"
            guard !prefix.isEmpty else { return count }
            let hex = prefix.map { String(format: "%02X", $0) }.joined(separator: " ")
            return "\(count) · \(hex)\(size > prefix.count ? "…" : "")"
        }
    }
#endif
