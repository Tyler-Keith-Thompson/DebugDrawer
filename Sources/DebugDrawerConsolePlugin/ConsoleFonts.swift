#if DEBUG && os(iOS)
    import SwiftUI
    import UIKit

    /// The console's font on iOS, scaled for a Dynamic Type size: the drawer's code type, the
    /// footnote style monospaced, for the times and the text alike.
    struct ConsoleFonts {
        let code: UIFont

        /// The font at a text size.
        ///
        /// - Parameter dynamicTypeSize: The text size the console draws at; at `.large`, the
        ///   default, the font is the footnote's 13 pt.
        init(dynamicTypeSize: DynamicTypeSize) {
            // UIKit draws the text, so SwiftUI's environment doesn't scale it; UIFontMetrics scales
            // the footnote's size the way the footnote style grows.
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
            let metrics = UIFontMetrics(forTextStyle: .footnote)
            let base = UIFont.preferredFont(forTextStyle: .footnote, compatibleWith: UITraitCollection(preferredContentSizeCategory: .large))
            code = metrics.scaledFont(for: .monospacedSystemFont(ofSize: base.pointSize, weight: .regular), compatibleWith: traits)
        }
    }
#endif
