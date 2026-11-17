#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The translations a language is missing: a picker of the app's languages, then the keys it
    /// lacks grouped by table under a filter, each with its development text, then Copy as Text,
    /// Copy as CSV and Refresh. An app with one language says there's nothing to compare.
    struct MissingTranslationsSection: View {
        /// The language compared with the development language.
        @Binding var language: String
        @Binding var query: String
        let bundles: [LocalizedBundle]
        let lookups: [LocalizationLookup]
        let onRefresh: () -> Void
        @Environment(\.locale) private var locale
        /// The tallest the list grows before it scrolls.
        @ScaledMetric(relativeTo: .body) private var listHeight: CGFloat = 300

        var body: some View {
            let localizations = bundles.localizations
            if localizations.count < 2 {
                DebugDrawerSection("Missing Translations") {
                    EmptyView()
                } footer: {
                    Text(singleLanguageNote(localizations))
                }
            } else {
                content(localizations: localizations)
            }
        }

        private func content(localizations: [String]) -> some View {
            let missing = MissingTranslation.find(in: bundles, localization: language, lookups: lookups)
            let matching = missing.filter { $0.matches(query) }
            return VStack(alignment: .leading, spacing: 0) {
                DebugDrawerSection("Missing Translations") {
                    DebugDrawerRow("Language") {
                        Picker("Language", selection: $language) {
                            ForEach(localizations, id: \.self) { localization in
                                Text(verbatim: displayName(of: localization)).tag(localization)
                            }
                        }
                        .accessibilityLabel("Language to compare")
                    }
                    if !missing.isEmpty {
                        DebugDrawerSearchableList(
                            "Filter keys…",
                            text: $query,
                            accessibilityLabel: "Filter missing translations by key or text",
                            maxHeight: listHeight
                        ) {
                            ForEach(matching.grouped, id: \.name) { group in
                                Text(verbatim: group.name)
                                    .debugDrawerFont(.heading)
                                    .debugDrawerForegroundStyle(.secondary)
                                    .debugDrawerRowPadding()
                                    .accessibilityAddTraits(.isHeader)
                                ForEach(group.items) { item in
                                    MissingTranslationRow(item: item)
                                }
                            }
                        }
                    }
                } footer: {
                    Text(note(missing: missing.count, matching: matching.count))
                }
                DebugDrawerActionRow {
                    if !missing.isEmpty {
                        DebugDrawerCopyButton("Copy as Text") { MissingTranslation.text(of: missing, language: language) }
                        DebugDrawerCopyButton("Copy as CSV") { MissingTranslation.csv(of: missing) }
                    }
                } trailing: {
                    Button("Refresh", action: onRefresh)
                        .debugDrawerButtonStyle(.borderless)
                        .accessibilityHint("Reads the app's tables again")
                }
            }
        }

        /// The language's name in the drawer's locale, then its code: "German (de)".
        private func displayName(of localization: String) -> String {
            guard let name = locale.localizedString(forIdentifier: localization), name != localization else { return localization }
            return "\(name) (\(localization))"
        }

        /// How many translations are missing, against which language, or that the filter matches
        /// none.
        private func note(missing: Int, matching: Int) -> String {
            let development = bundles.developmentLocalization ?? "the development language"
            if missing == 0 {
                return language == development
                    ? "\(language) is the development language, and every string the app looked up is in its tables."
                    : "Every string in \(development) has a \(language) translation."
            }
            if matching == 0 {
                return "No missing translation matches “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”."
            }
            let strings = missing == 1 ? "1 string has" : "\(missing.formatted()) strings have"
            return "\(strings) no \(language) translation. Looked up: the app asked for the key while running and got none."
        }

        /// Why there is nothing to compare.
        private func singleLanguageNote(_ localizations: [String]) -> String {
            if let only = localizations.first {
                return "The app's strings are in \(only) only, so no translation can be missing. Add a language to its tables to compare."
            }
            return "The app's bundles hold no .strings or .stringsdict table."
        }
    }

    /// A missing translation: its key in code type, cut in the middle, and below it the
    /// development text, or that no table has the key; "Looked up" when the app asked for it.
    struct MissingTranslationRow: View {
        let item: MissingTranslation
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: item.key)
                        .debugDrawerFont(.code)
                        .debugDrawerForegroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .truncationMode(.middle)
                        .help(item.key)
                    Text(verbatim: item.developmentValue ?? "No table has this key")
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if item.isLookedUp {
                    Text("Looked up")
                        .debugDrawerFont(.label)
                        .debugDrawerForegroundStyle(.tertiary)
                }
            }
            .debugDrawerRowPadding()
            .accessibilityElement(children: .combine)
        }
    }

    /// The missing translations of one table, as the list heads them.
    private struct MissingTranslationGroup {
        let name: String
        var items: [MissingTranslation]
    }

    extension [MissingTranslation] {
        /// The translations in their groups, in order: a group's items are consecutive, as
        /// ``MissingTranslation/find(in:localization:lookups:)`` sorts them.
        fileprivate var grouped: [MissingTranslationGroup] {
            reduce(into: []) { groups, item in
                if groups.last?.name == item.group {
                    groups[groups.count - 1].items.append(item)
                } else {
                    groups.append(MissingTranslationGroup(name: item.group, items: [item]))
                }
            }
        }
    }

    extension MissingTranslation {
        /// Whether `query`, trimmed, appears in the key, the development text or the group,
        /// ignoring case; an empty query matches everything.
        fileprivate func matches(_ query: String) -> Bool {
            let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty else { return true }
            return [key, developmentValue ?? "", group].contains { $0.localizedStandardContains(term) }
        }
    }
#endif
