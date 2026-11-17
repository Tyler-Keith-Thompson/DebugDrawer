#if DEBUG
    /// A string a language has no translation for: a key its development language has, or one the
    /// app looked up, that the language's table lacks.
    struct MissingTranslation: Hashable, Sendable, Identifiable {
        /// The table it belongs in, after its bundle's name for a bundle other than the main one.
        let group: String
        let key: String
        /// The development language's text, or the default value the app passed when no table
        /// has the key; `nil` when neither does.
        let developmentValue: String?
        /// Whether the app looked the key up while running and got no translation.
        let isLookedUp: Bool

        var id: String {
            group + "\u{1F}" + key
        }

        /// The translations `localization` is missing in `bundles`, sorted by group, then key:
        /// every key of each bundle's development tables (Base folded in) that the localization's
        /// table of the same name lacks, and every looked-up key that table lacks, marked looked
        /// up. A bundle with no folder for the localization is missing every key, unless it has
        /// one localization only: then it isn't localized, and lacks nothing. The development
        /// localization lacks only the looked-up keys that no table has.
        ///
        /// - Complexity: O(*n* log *n*), where *n* is the number of keys in the bundles' tables.
        static func find(in bundles: [LocalizedBundle], localization: String, lookups: [LocalizationLookup]) -> [MissingTranslation] {
            var missing: [String: MissingTranslation] = [:]
            for bundle in bundles where bundle.localizations.count > 1 || bundle.localizations.contains(localization) {
                let development = bundle.developmentTables
                // Base holds the development language's text (a storyboard's), so it counts as
                // translated for the development localization alone.
                let translatedTables = localization == bundle.developmentLocalization ? development : bundle.tables[localization] ?? []
                let translated = Dictionary(translatedTables.map { ($0.name, $0.entries) }, uniquingKeysWith: { first, _ in first })
                for table in development {
                    for (key, entry) in table.entries where translated[table.name]?[key] == nil {
                        let item = MissingTranslation(
                            group: bundle.groupName(ofTable: table.name), key: key, developmentValue: entry.value, isLookedUp: false
                        )
                        missing[item.id] = item
                    }
                }
                let developmentEntries = Dictionary(development.map { ($0.name, $0.entries) }, uniquingKeysWith: { first, _ in first })
                for lookup in lookups where lookup.bundlePath == bundle.path && translated[lookup.table]?[lookup.key] == nil {
                    let item = MissingTranslation(
                        group: bundle.groupName(ofTable: lookup.table),
                        key: lookup.key,
                        developmentValue: developmentEntries[lookup.table]?[lookup.key]?.value ?? lookup.defaultValue,
                        isLookedUp: true
                    )
                    missing[item.id] = item
                }
            }
            return missing.values.sorted { ($0.group, $0.key) < ($1.group, $1.key) }
        }
    }
#endif
