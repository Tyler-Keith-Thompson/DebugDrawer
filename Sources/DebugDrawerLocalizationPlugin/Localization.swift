import Foundation

/// Localization tools in the debug drawer: pseudo-localization, the keys shown in place of their
/// strings, and the translations a language is missing, so layouts that clip, strings that were
/// never localized and gaps in a translation show before a translator or a user finds them.
///
/// ```swift
/// Localization.install()
/// ```
///
/// The modes rewrite the strings the app's own bundles return from `Bundle`'s public lookups:
/// `NSLocalizedString`, `Bundle.localizedString(forKey:value:table:)` and the code that calls
/// them. SwiftUI's `Text` and `String(localized:)` look strings up through Foundation API outside
/// that path, so the modes leave them as they are; the plugin lists Apple's launch arguments that
/// change every string at launch instead.
///
/// The type exists in every build, so the call compiles unchanged in release, where it does
/// nothing and intercepts nothing.
public enum Localization {
    /// What the app's strings show.
    public enum Mode: String, CaseIterable, Sendable {
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

    /// Adds the Localization plugin and starts intercepting the app's string lookups: in debug
    /// builds only; in release it does nothing.
    ///
    /// The plugin reads every `.strings` and `.stringsdict` table of the app's bundles (the main
    /// bundle and the bundles inside it) and records, from then on, the keys the app looks up and
    /// gets no translation for. Call it once at startup, before the first string is looked up,
    /// so the lookups at launch are recorded too. Calling it again replaces the plugin and sets
    /// the mode. Removing the plugin from the drawer puts the lookups back.
    ///
    /// - Parameter mode: What the app's strings show until the drawer changes it, such as
    ///   ``Mode/pseudoLocalized`` for a launch argument of the app's own.
    @MainActor
    public static func install(mode: Mode = .standard) {
        #if DEBUG
            LocalizationInstallation.install(mode: mode)
        #endif
    }
}
