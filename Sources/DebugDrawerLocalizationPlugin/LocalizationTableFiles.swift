#if DEBUG
    import DebugDrawer
    import Foundation

    /// Reads the tables of one `.lproj` folder: `.strings` files (text in the strings format,
    /// UTF-8 or UTF-16, or a binary or XML property list, as Xcode compiles them and a String
    /// Catalog becomes) and `.stringsdict` files. Reading them is the drawer's own work, which
    /// Disk I/O leaves out.
    enum LocalizationTableFiles {
        /// The folder's tables, sorted by name. A `.strings` and a `.stringsdict` of the same name
        /// are one table, the stringsdict winning for a key in both, as Foundation's lookup does.
        /// A file that isn't a dictionary of strings is skipped.
        static func tables(in folder: URL) -> [LocalizationTable] {
            DebugDrawerActivity.$isDrawerWork.withValue(true) { readTables(in: folder) }
        }

        private static func readTables(in folder: URL) -> [LocalizationTable] {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            var entries: [String: [String: LocalizationEntry]] = [:]
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let name = file.deletingPathExtension().lastPathComponent
                switch file.pathExtension {
                case "strings":
                    if let strings = strings(at: file) {
                        entries[name, default: [:]].merge(strings) { existing, _ in existing }
                    }
                case "stringsdict":
                    if let plurals = stringsdict(at: file) {
                        entries[name, default: [:]].merge(plurals) { _, plural in plural }
                    }
                default:
                    break
                }
            }
            return entries.keys.sorted().map { LocalizationTable(name: $0, entries: entries[$0] ?? [:]) }
        }

        /// A `.strings` file's entries, or `nil` when it can't be read as one.
        static func strings(at file: URL) -> [String: LocalizationEntry]? {
            guard let data = try? Data(contentsOf: file),
                  let dictionary = propertyList(data) as? [String: Any]
            else { return nil }
            return dictionary.compactMapValues { ($0 as? String).map { LocalizationEntry($0) } }
        }

        /// A `.stringsdict` file's entries, each the format with its variables' `other` variants
        /// filled in (`%lld items`), or `nil` when it can't be read as one.
        static func stringsdict(at file: URL) -> [String: LocalizationEntry]? {
            guard let data = try? Data(contentsOf: file),
                  let dictionary = propertyList(data) as? [String: Any]
            else { return nil }
            return dictionary.compactMapValues { value in
                (value as? [String: Any]).map { LocalizationEntry($0.pluralSummary, isPlural: true) }
            }
        }

        /// The property list in `data`; text in the strings format is one too, which needs
        /// decoding first when it is UTF-16.
        private static func propertyList(_ data: Data) -> Any? {
            if let list = try? PropertyListSerialization.propertyList(from: data, format: nil) {
                return list
            }
            guard let text = String(data: data, encoding: .utf16) ?? String(data: data, encoding: .utf8) else { return nil }
            return try? PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil)
        }
    }

    extension [String: Any] {
        /// A stringsdict entry in words: its format string with each `%#@variable@` replaced by
        /// that variable's `other` variant.
        fileprivate var pluralSummary: String {
            guard let format = self["NSStringLocalizedFormatKey"] as? String else { return "" }
            return format.formatTokens.map { token in
                switch token {
                case let .literal(text):
                    return text
                case let .specifier(specifier):
                    guard specifier.hasPrefix("%#@"),
                          let variable = self[String(specifier.dropFirst(3).dropLast())] as? [String: Any],
                          let other = variable["other"] as? String
                    else { return specifier }
                    return other
                }
            }
            .joined()
        }
    }
#endif
