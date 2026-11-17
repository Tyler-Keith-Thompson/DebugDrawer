#if DEBUG
    /// One of Foundation's own localization settings, which it reads from the app's defaults at
    /// launch and applies to every string looked up after, SwiftUI's `Text` and
    /// `String(localized:)` included.
    enum NextLaunchOption: String, CaseIterable, Hashable, Sendable {
        /// Every string accented and doubled in length.
        case pseudoLocalized
        /// Every string with no translation in capitals.
        case untranslatedInCapitals

        /// The defaults keys Foundation reads for it, each set to `true`.
        var defaultsKeys: [String] {
            switch self {
            case .pseudoLocalized: ["NSAccentuateLocalizedStrings", "NSDoubleLocalizedStrings"]
            case .untranslatedInCapitals: ["NSShowNonLocalizedStrings"]
            }
        }

        /// The name the plugin shows.
        var title: String {
            switch self {
            case .pseudoLocalized: "Accented and Doubled"
            case .untranslatedInCapitals: "Untranslated in Capitals"
            }
        }
    }

    extension Set<NextLaunchOption> {
        /// The options in the order the plugin lists them, joined for a summary: "Accented and
        /// Doubled, Untranslated in Capitals".
        var summary: String {
            NextLaunchOption.allCases.filter(contains).map(\.title).joined(separator: ", ")
        }
    }
#endif
