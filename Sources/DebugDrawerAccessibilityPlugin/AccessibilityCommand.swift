import Foundation

// Public because it is `AccessibilityModel`'s `Command`, and opaque: the actions it wraps stay
// internal, as their payloads are the plugin's own types. An enum's cases share its access level,
// so the public type is a struct around the internal enum.

#if DEBUG
    /// Something the Accessibility plugin's view asks ``AccessibilityModel`` to do: override a
    /// value, return it to the system's, or clear every override. `Codable`, so a transport can
    /// carry it from another process.
    public struct AccessibilityCommand: Codable, Sendable {
        /// What to do. A `nil` value returns that override to the system's.
        enum Action: Codable, Sendable {
            case setColorScheme(AccessibilityOverrideValues.ColorScheme?)
            case setDynamicTypeSize(AccessibilityOverrideValues.DynamicTypeSize?)
            case setLayoutDirection(AccessibilityOverrideValues.LayoutDirection?)
            /// A locale's identifier ("fr").
            case setLocale(String?)
            case setSetting(AccessibilitySetting, Bool?)
            /// Clears every override.
            case reset
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds override nothing: this stand-in asks for nothing.
    public struct AccessibilityCommand: Codable, Sendable {}
#endif
