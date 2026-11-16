import SwiftUI

/// The drawer's text colors, for text a plugin lays out itself rather than in one of the drawer's
/// rows (which color their own): a log line's timestamp, a count beside a name, an error message.
///
/// Apply one with `debugDrawerForegroundStyle(_:)`. Each is a light and a dark color that meet
/// 4.5:1 on the panel.
public enum DebugDrawerForegroundStyle: CaseIterable, Sendable {
    /// Ordinary text.
    case primary
    /// Text that supports what's beside it: a detail, a summary.
    case secondary
    /// Text that recedes further: a timestamp, a key's type, an index.
    case tertiary
    /// Text that can be pressed or names what is selected.
    case accent
    /// Text that reports a failure, always with words that say so.
    case error
}

public extension View {
    /// Colors the text and symbols in this view in one of the drawer's
    /// ``DebugDrawerForegroundStyle`` colors. Inside a view drawn `debugDrawerSelected(_:)`, the
    /// colors that read on the selection fill.
    ///
    /// In release it changes nothing, so a caller compiles unchanged.
    func debugDrawerForegroundStyle(_ style: DebugDrawerForegroundStyle) -> some View {
        #if DEBUG
            modifier(DrawerForegroundStyle(style: style))
        #else
            self
        #endif
    }
}

#if DEBUG
    /// Colors text in a ``DebugDrawerForegroundStyle``, or on the selection fill in white, the
    /// supporting styles dimmed as the selected stack frame dims its index and image.
    struct DrawerForegroundStyle: ViewModifier {
        let style: DebugDrawerForegroundStyle
        @Environment(\.debugDrawerIsSelected) private var isSelected

        func body(content: Content) -> some View {
            content.foregroundStyle(isSelected ? style.colorOnSelection : style.color)
        }
    }

    extension DebugDrawerForegroundStyle {
        /// The style's color on the selection fill.
        var colorOnSelection: Color {
            switch self {
            case .primary, .accent, .error: DrawerPalette.onSelection
            case .secondary, .tertiary: DrawerPalette.onSelection.opacity(0.78)
            }
        }

        /// The style's color.
        var color: Color {
            switch self {
            case .primary: DrawerPalette.text
            case .secondary: DrawerPalette.secondaryText
            case .tertiary: DrawerPalette.tertiaryText
            case .accent: DrawerPalette.accent
            case .error: DrawerPalette.errorText
            }
        }
    }
#endif
