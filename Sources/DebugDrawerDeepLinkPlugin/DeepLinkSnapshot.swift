import Foundation

// Public because it is `DeepLinkModel`'s `Snapshot`, and opaque: its fields stay internal, so a
// reader outside the module carries it whole, encoded. The outcome is a value; the view words it
// and picks its glyph.

#if DEBUG
    /// Everything the Deep Link Tester shows, as a value: the URL being typed, the presets, the
    /// URLs opened and activities continued before, and what came of the last send.
    ///
    /// ``DeepLinkModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport can
    /// carry it.
    public struct DeepLinkSnapshot: Codable, Equatable, Sendable {
        /// The text in the URL field.
        var urlText = ""
        /// The URLs listed under Presets.
        var presets: [DeepLinkPreset] = []
        /// URLs opened, most recent first.
        var history: [String] = []
        /// Activities continued, most recent first, apart from the URLs opened.
        var activities: [DeepLinkActivity] = []
        /// What came of the last send; nil before one.
        var outcome: DeepLinkOutcome?
    }
#else
    /// Release builds open no URLs: this stand-in holds nothing.
    public struct DeepLinkSnapshot: Codable, Equatable, Sendable {}
#endif
