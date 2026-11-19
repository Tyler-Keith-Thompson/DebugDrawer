#if DEBUG
    import Foundation

    /// The system's own value of each accessibility setting, whatever the plugin overrides.
    struct AccessibilitySystemValues: Codable, Equatable, Sendable {
        var reduceMotion = false
        var increaseContrast = false
        var boldText = false
        var reduceTransparency = false
        var differentiateWithoutColor = false
        var invertColors = false

        /// The system's value of `setting`.
        subscript(setting: AccessibilitySetting) -> Bool {
            switch setting {
            case .reduceMotion: reduceMotion
            case .increaseContrast: increaseContrast
            case .boldText: boldText
            case .reduceTransparency: reduceTransparency
            case .differentiateWithoutColor: differentiateWithoutColor
            case .invertColors: invertColors
            }
        }
    }
#endif
