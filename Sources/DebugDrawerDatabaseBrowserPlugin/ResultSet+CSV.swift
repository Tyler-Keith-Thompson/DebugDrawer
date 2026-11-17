#if DEBUG
    extension ResultSet {
        /// The rows as CSV (RFC 4180): a header of column names, then a line per row, ended by
        /// CRLF. A field holding a comma, a double quote or a line break is quoted, its quotes
        /// doubled. NULL is an empty field; a real is every digit it needs to read back the same;
        /// a blob, as its cell shows it, its size and first bytes.
        var csv: String {
            let lines = [columns.map(\.csvField)] + rows.map { $0.map(\.csvField) }
            return lines.map { $0.joined(separator: ",") + "\r\n" }.joined()
        }
    }

    extension SQLiteValue {
        fileprivate var csvField: String {
            switch self {
            case .null: ""
            // In full, unlike the cell: a spreadsheet should get the stored value.
            case let .real(value): String(value)
            case .integer, .text, .blob: displayText.csvField
            }
        }
    }

    extension String {
        fileprivate var csvField: String {
            // By scalar: "\r\n" is one Character, so a lone "\n" wouldn't match it.
            guard unicodeScalars.contains(where: { ",\"\r\n".unicodeScalars.contains($0) }) else { return self }
            return "\"" + replacing("\"", with: "\"\"") + "\""
        }
    }
#endif
