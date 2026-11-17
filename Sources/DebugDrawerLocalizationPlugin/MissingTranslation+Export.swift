#if DEBUG
    extension MissingTranslation {
        /// The translations as text, a heading for each group and a line for each key with its
        /// development text in quotes, marked when it was looked up:
        ///
        /// ```
        /// Missing in de (2):
        /// Localizable
        ///   settings.privacy = "Privacy Policy"
        ///   banner.new = "New: faster checkout" (looked up)
        /// ```
        static func text(of missing: [MissingTranslation], language: String) -> String {
            var lines = ["Missing in \(language) (\(missing.count)):"]
            var group: String?
            for item in missing {
                if item.group != group {
                    lines.append(item.group)
                    group = item.group
                }
                let value = item.developmentValue.map { " = \"\($0)\"" } ?? ""
                lines.append("  \(item.key)\(value)\(item.isLookedUp ? " (looked up)" : "")")
            }
            return lines.joined(separator: "\n")
        }

        /// The translations as CSV, with a header row: table, key, development text and whether it
        /// was looked up. A field with a comma, a quote or a line break is quoted, its quotes
        /// doubled (RFC 4180).
        static func csv(of missing: [MissingTranslation]) -> String {
            let rows = [["table", "key", "development value", "looked up"]] + missing.map { item in
                [item.group, item.key, item.developmentValue ?? "", item.isLookedUp ? "yes" : "no"]
            }
            return rows.map { $0.map(\.csvField).joined(separator: ",") }.joined(separator: "\r\n")
        }
    }

    extension String {
        /// The text as one CSV field.
        fileprivate var csvField: String {
            guard contains(where: { ",\"\r\n".contains($0) }) else { return self }
            return "\"" + replacing("\"", with: "\"\"") + "\""
        }
    }
#endif
