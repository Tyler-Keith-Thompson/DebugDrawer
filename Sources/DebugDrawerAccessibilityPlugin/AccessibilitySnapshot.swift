import Foundation

// Public because it is `AccessibilityModel`'s `Snapshot`, and opaque: its fields stay internal, so
// the plugin's value types don't become API. A reader outside the module carries it whole, encoded.

#if DEBUG
    /// Everything the Accessibility plugin shows, as a value: what is overridden, the system's
    /// own accessibility settings, and the locales the app is localized into.
    ///
    /// ``AccessibilityModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport
    /// can carry it to another process.
    public struct AccessibilitySnapshot: Codable, Equatable, Sendable {
        /// What the developer has overridden.
        var overrides = AccessibilityOverrideValues()
        /// The system's own value of each accessibility setting.
        var system = AccessibilitySystemValues()
        /// The identifiers of the locales the app is localized into, sorted.
        var availableLocales: [String] = []
    }
#else
    /// Release builds override nothing: this stand-in holds nothing.
    public struct AccessibilitySnapshot: Codable, Equatable, Sendable {}
#endif
