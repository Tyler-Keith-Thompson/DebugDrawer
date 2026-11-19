#if DEBUG
    import Foundation

    /// One of the system accessibility settings SwiftUI reads, which the plugin shows the system's
    /// value of and can override.
    enum AccessibilitySetting: String, CaseIterable, Codable, Sendable {
        /// Reduce Motion, SwiftUI's `accessibilityReduceMotion`.
        case reduceMotion
        /// Increase Contrast, SwiftUI's `colorSchemeContrast`.
        case increaseContrast
        /// Bold Text, SwiftUI's `legibilityWeight`.
        case boldText
        /// Reduce Transparency, SwiftUI's `accessibilityReduceTransparency`.
        case reduceTransparency
        /// Differentiate Without Color, SwiftUI's `accessibilityDifferentiateWithoutColor`.
        case differentiateWithoutColor
        /// Invert Colors, SwiftUI's `accessibilityInvertColors`.
        case invertColors
    }
#endif
