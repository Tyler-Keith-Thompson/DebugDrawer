#if DEBUG
    /// A bundle's localized strings, as its `.lproj` folders hold them: each localization's
    /// tables, with the development localization they are translated from.
    struct LocalizedBundle: Hashable, Sendable {
        /// The bundle's file name (`DebugDrawerExample.app`, `Kit.framework`).
        let name: String
        /// Its path, standardized, as a lookup records it.
        let path: String
        /// Whether it is the app's main bundle.
        let isMain: Bool
        /// The localization the app's strings are written in (`CFBundleDevelopmentRegion`).
        let developmentLocalization: String
        /// The localization Foundation picks for it from the user's languages: the current one.
        let preferredLocalization: String?
        /// Each localization's tables, by the localization's name (`en`, `de`, `Base`).
        let tables: [String: [LocalizationTable]]

        /// The localizations it has, `Base` aside, sorted.
        var localizations: [String] {
            tables.keys.filter { $0 != Self.base }.sorted()
        }

        /// The name of the folder of strings shared by every localization.
        static let base = "Base"

        /// The development localization's tables, `Base` folded in: what every translation is
        /// compared with. A table in both has the development localization's entries win.
        var developmentTables: [LocalizationTable] {
            LocalizationTable.merging(tables[Self.base] ?? [], over: tables[developmentLocalization] ?? [])
        }

        /// The group its tables are listed under: the table's name, after the bundle's for a
        /// bundle other than the main one (`Kit.framework · Localizable`).
        func groupName(ofTable table: String) -> String {
            isMain ? table : "\(name) · \(table)"
        }
    }

    extension [LocalizedBundle] {
        /// The main bundle, or the first when none is.
        private var main: LocalizedBundle? {
            first { $0.isMain } ?? first
        }

        /// The localization the app runs in: the one Foundation picks for the main bundle.
        var currentLocalization: String? {
            main?.preferredLocalization
        }

        /// The language the app's strings are written in: the main bundle's development
        /// localization.
        var developmentLocalization: String? {
            main?.developmentLocalization
        }

        /// Every localization of the bundles, `Base` aside, sorted.
        var localizations: [String] {
            Set(flatMap(\.localizations)).sorted()
        }
    }

    /// One table of strings in one localization: `Localizable` is `Localizable.strings` and
    /// `Localizable.stringsdict` together.
    struct LocalizationTable: Hashable, Sendable {
        /// The table's name, which a lookup passes as `table` (`nil` is `Localizable`).
        let name: String
        /// Each key's text: a plural's is its format with the `other` variants filled in.
        let entries: [String: LocalizationEntry]

        /// The table a lookup with no table name reads.
        static let defaultName = "Localizable"

        /// `tables` with `overrides` laid over them: a table in both has the override's entries
        /// win, key by key.
        static func merging(_ tables: [LocalizationTable], over overrides: [LocalizationTable]) -> [LocalizationTable] {
            var merged = Dictionary(tables.map { ($0.name, $0.entries) }, uniquingKeysWith: { $0.merging($1) { $1 } })
            for table in overrides {
                merged[table.name, default: [:]].merge(table.entries) { $1 }
            }
            return merged.keys.sorted().map { LocalizationTable(name: $0, entries: merged[$0] ?? [:]) }
        }
    }

    /// A string in a table: its text, and whether a stringsdict holds it as a plural.
    struct LocalizationEntry: Hashable, Sendable {
        let value: String
        let isPlural: Bool

        init(_ value: String, isPlural: Bool = false) {
            self.value = value
            self.isPlural = isPlural
        }
    }
#endif
