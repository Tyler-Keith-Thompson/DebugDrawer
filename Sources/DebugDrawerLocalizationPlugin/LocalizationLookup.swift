#if DEBUG
    /// A key the app looked up and got no translation for: the lookup returned the key itself or
    /// the default value it passed.
    struct LocalizationLookup: Hashable, Sendable {
        /// The bundle's path, standardized.
        let bundlePath: String
        /// The table it was looked up in.
        let table: String
        let key: String
        /// The default value the lookup passed, if any: what the app showed in its place.
        let defaultValue: String?

        /// - Parameter table: `nil` or empty is ``LocalizationTable/defaultName``.
        /// - Parameter defaultValue: Empty is none.
        init(bundlePath: String, table: String?, key: String, defaultValue: String?) {
            self.bundlePath = bundlePath
            self.table = table.flatMap { $0.isEmpty ? nil : $0 } ?? LocalizationTable.defaultName
            self.key = key
            self.defaultValue = defaultValue.flatMap { $0.isEmpty ? nil : $0 }
        }

        /// Whether a lookup that returned `result` found no translation: it returned the key, or
        /// the default value in place of one.
        static func isUntranslated(key: String, defaultValue: String?, result: String) -> Bool {
            !key.isEmpty && (result == key || (defaultValue?.isEmpty == false && result == defaultValue))
        }
    }
#endif
