#if DEBUG && os(iOS)
    import SwiftUI
    import UIKit

    /// The console's fonts on iOS, scaled for a Dynamic Type size: log text, timestamps and level
    /// badges, each monospaced.
    struct ConsoleFonts {
        let text: UIFont
        let small: UIFont
        let badge: UIFont

        /// The fonts at a text size.
        ///
        /// - Parameter dynamicTypeSize: The text size the console draws at; at `.large`, the
        ///   default, the log text is 10 pt, the timestamps 9 pt and the badges 8 pt.
        init(dynamicTypeSize: DynamicTypeSize) {
            // UIKit draws the text, so SwiftUI's environment doesn't scale it; UIFontMetrics scales
            // each base size the way the caption styles grow.
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
            let metrics = UIFontMetrics(forTextStyle: .caption2)
            func scaled(_ size: CGFloat, _ weight: UIFont.Weight) -> UIFont {
                metrics.scaledFont(for: .monospacedSystemFont(ofSize: size, weight: weight), compatibleWith: traits)
            }
            text = scaled(10, .regular)
            small = scaled(9, .regular)
            badge = scaled(8, .bold)
        }
    }
#endif
