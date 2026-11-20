// The namespace and its modes live here, in every build, so the receiver's localization review
// (`LocalizationReview`) and the drawer's Localization plugin speak of the same modes; the plugin
// re-exports this module and adds `install(mode:)`.

/// Localization tools in the debug drawer: pseudo-localization, the keys shown in place of their
/// strings, and the translations a language is missing, so layouts that clip, strings that were
/// never localized and gaps in a translation show before a translator or a user finds them.
///
/// ```swift
/// Localization.install()
/// ```
///
/// In the drawer, the modes rewrite the strings the app's own bundles return from `Bundle`'s
/// public lookups: `NSLocalizedString`, `Bundle.localizedString(forKey:value:table:)` and the code
/// that calls them. SwiftUI's `Text` and `String(localized:)` look strings up through Foundation
/// API outside that path, so the modes leave them as they are; the plugin lists Apple's launch
/// arguments that change every string at launch instead.
///
/// `install(mode:)` comes with the Localization plugin and exists in every build, so the call
/// compiles unchanged in release, where it does nothing and intercepts nothing. In a release build
/// a sidecar sets a mode through ``LocalizationReview`` instead, for the strings the app reads
/// through it.
public enum Localization {
    /// What the app's strings show.
    public enum Mode: String, CaseIterable, Codable, Sendable {
        /// Each string as its table translates it.
        case standard
        /// Each string accented, about 40% longer and in brackets (`[Šéţţîñĝš····]`), with its
        /// format specifiers and plural variants intact, so clipped, truncated and hard-coded
        /// text shows.
        case pseudoLocalized
        /// Each string's key in place of its translation, so a tester can name the string to
        /// fix.
        case showingKeys
    }
}
