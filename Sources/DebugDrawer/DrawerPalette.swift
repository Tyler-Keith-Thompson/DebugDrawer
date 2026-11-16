#if DEBUG
    import SwiftUI

    #if os(macOS)
        import AppKit
    #elseif canImport(UIKit)
        import UIKit
    #endif

    /// The drawer's colors, each a light and a dark variant that follow the appearance, in the
    /// manner of Xcode's own panes: one flat surface divided by hairlines, color only where it
    /// means something (the accent for what can be pressed or is selected; error, warning and ok
    /// for an issue, always beside a word or a glyph's shape).
    ///
    /// Text colors meet 4.5:1 on the panel and the well: tertiary text is darker in light
    /// (0x6A6A6F rather than 0x86868B) and lighter in dark (0x89898F rather than 0x7E7E84) than
    /// the design's, and error text, kept apart from the glyphs' red, is 0xD72C22 / 0xFF7C74.
    enum DrawerPalette {
        /// The whole drawer, one surface.
        static let panel = Color(light: 0xF6F6F6, dark: 0x232326)
        /// Set into the panel: the jump bar and a code block.
        static let well = Color(light: 0xECECEC, dark: 0x1B1B1D)
        /// Behind a text field's text.
        static let field = Color(light: 0xFFFFFF, dark: 0x1B1B1D)
        /// Hairlines, a field's edge, a gauge's track and a count's capsule.
        static let separator = Color(light: 0xDCDCDE, dark: 0x3A3A3E)
        static let text = Color(light: 0x1D1D1F, dark: 0xE6E6E8)
        static let secondaryText = Color(light: 0x5F5F64, dark: 0xA3A3A8)
        static let tertiaryText = Color(light: 0x6A6A6F, dark: 0x89898F)
        /// What can be pressed, and a gauge's fill.
        static let accent = Color(light: 0x0A63D6, dark: 0x3E8BFF)
        /// A selected row, and a primary button, with ``onSelection`` text: the dark accent is too
        /// light under white text, so both take this.
        static let selection = Color(light: 0x0A63D6, dark: 0x2F6BDB)
        static let onSelection = Color.white
        /// A selected tab and an active toggle, under an accent symbol.
        static let softSelection = Color(light: 0xDCE8FA, dark: 0x20324F)
        /// An error glyph and the unread dot.
        static let error = Color(light: 0xE0352B, dark: 0xFF5F57)
        /// Error text, as a destructive button's title.
        static let errorText = Color(light: 0xD72C22, dark: 0xFF7C74)
        /// A warning glyph's fill, and the mark drawn on it.
        static let warning = Color(light: 0xF5B400, dark: 0xFFC22E)
        static let warningMark = Color(light: 0x3A2A00, dark: 0x3A2A00)
        static let ok = Color(light: 0x28A745, dark: 0x32C25B)
        /// A badge that isn't the app's own: a system frame, a dylib, an issue not yet decided.
        static let systemGray = Color(light: 0xA6A6AB, dark: 0x5C5C62)
        /// A framework's type badge.
        static let framework = Color(light: 0xC98A12, dark: 0xC98A12)
        /// A push button's face, its edge, and the 1 pt shadow below it.
        static let pushFill = Color(light: 0xFFFFFF, dark: 0x3A3A3E)
        static let pushBorder = Color(light: 0xCBCBCF, dark: 0x4A4A4F)
        static let pushShadow = Color(light: 0xD4D4D8, dark: 0x141416)
    }

    extension DrawerPalette {
        /// What a gauge's bar or a graph's line is filled with: an issue's color where that
        /// means something, the accent otherwise.
        static func fill(for severity: DebugDrawerIssueGlyph.Severity?) -> Color {
            switch severity {
            case nil: accent
            case .error: error
            case .warning: warning
            case .ok: ok
            case .neutral: systemGray
            }
        }
    }

    extension Color {
        /// A color that is `light` in the light appearance and `dark` in the dark one, each as
        /// 0xRRGGBB in sRGB. The watch is always dark.
        fileprivate init(light: UInt32, dark: UInt32) {
            #if os(macOS)
                self.init(nsColor: NSColor(name: nil) { appearance in
                    let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    return NSColor(rgb: isDark ? dark : light)
                })
            #elseif os(watchOS)
                self.init(uiColor: UIColor(rgb: dark))
            #else
                self.init(uiColor: UIColor { traits in
                    UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
                })
            #endif
        }
    }

    extension PlatformColor {
        /// The sRGB color written 0xRRGGBB.
        fileprivate convenience init(rgb: UInt32) {
            self.init(
                red: CGFloat((rgb >> 16) & 0xFF) / 255,
                green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255,
                alpha: 1
            )
        }
    }
#endif
