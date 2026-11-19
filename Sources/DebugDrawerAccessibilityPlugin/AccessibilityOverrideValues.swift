#if DEBUG
    import Foundation

    // SwiftUI's ColorScheme, DynamicTypeSize and LayoutDirection aren't Codable, and the model holds
    // no SwiftUI types, so the overrides are described with these mirrors of them, case for case;
    // `AccessibilityOverrides+Store.swift` translates between the two.

    /// What the Accessibility plugin overrides, each `nil` while the system's value applies.
    struct AccessibilityOverrideValues: Codable, Equatable, Sendable {
        /// SwiftUI's `ColorScheme`.
        enum ColorScheme: String, Codable, Sendable {
            case light
            case dark
        }

        /// SwiftUI's `DynamicTypeSize`, smallest first.
        enum DynamicTypeSize: String, CaseIterable, Codable, Sendable {
            case xSmall
            case small
            case medium
            case large
            case xLarge
            case xxLarge
            case xxxLarge
            case accessibility1
            case accessibility2
            case accessibility3
            case accessibility4
            case accessibility5
        }

        /// SwiftUI's `LayoutDirection`.
        enum LayoutDirection: String, Codable, Sendable {
            case leftToRight
            case rightToLeft
        }

        var colorScheme: ColorScheme?
        var dynamicTypeSize: DynamicTypeSize?
        var layoutDirection: LayoutDirection?
        /// The locale's identifier ("fr").
        var locale: String?
        var reduceMotion: Bool?
        var increaseContrast: Bool?
        var boldText: Bool?
        var reduceTransparency: Bool?
        var differentiateWithoutColor: Bool?
        var invertColors: Bool?

        /// The override of `setting`, `nil` while the system's value applies.
        subscript(setting: AccessibilitySetting) -> Bool? {
            get {
                switch setting {
                case .reduceMotion: reduceMotion
                case .increaseContrast: increaseContrast
                case .boldText: boldText
                case .reduceTransparency: reduceTransparency
                case .differentiateWithoutColor: differentiateWithoutColor
                case .invertColors: invertColors
                }
            }
            set {
                switch setting {
                case .reduceMotion: reduceMotion = newValue
                case .increaseContrast: increaseContrast = newValue
                case .boldText: boldText = newValue
                case .reduceTransparency: reduceTransparency = newValue
                case .differentiateWithoutColor: differentiateWithoutColor = newValue
                case .invertColors: invertColors = newValue
                }
            }
        }

        /// Whether any value is overridden.
        var hasOverrides: Bool {
            self != AccessibilityOverrideValues()
        }
    }
#endif
