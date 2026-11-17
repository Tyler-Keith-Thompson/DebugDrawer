#if DEBUG
    extension String {
        /// The name as a quoted SQL identifier: in double quotes, any double quote in it doubled,
        /// so a table called `my "best" table` is `"my ""best"" table"`. Names are spliced into
        /// SQL only this way; values are always bound.
        var quotedSQLIdentifier: String {
            "\"" + replacing("\"", with: "\"\"") + "\""
        }

        /// The text as a `LIKE … ESCAPE '\'` pattern that matches it anywhere: `%`, `_` and `\`
        /// in it match only themselves.
        var containsLikePattern: String {
            let escaped = reduce(into: "") { pattern, character in
                if "%_\\".contains(character) {
                    pattern.append("\\")
                }
                pattern.append(character)
            }
            return "%" + escaped + "%"
        }
    }
#endif
