import SwiftUI

/// The drawer's type scale: the roles text plays in a plugin, each set in one of the platform's
/// text styles so it grows with Dynamic Type, through the accessibility sizes. iOS uses the
/// headline, body and footnote; the Mac, whose panes are compact, a step or two smaller.
///
/// Apply one with `debugDrawerFont(_:)`. Interface text, names and symbols included, is set in
/// the system font; monospaced type (``value`` and ``code``) is for numbers, versions, times,
/// paths, keys, code and JSON.
public enum DebugDrawerTextStyle: CaseIterable, Sendable {
    /// A plugin's title in its header row: bold.
    case title
    /// The name of a group of rows inside a plugin, in sentence case.
    case heading
    /// Ordinary text, row titles and button titles.
    case body
    /// The label beside a value, and other labels that name what's next to them.
    case label
    /// A value beside its label: monospaced, with figures of one width so columns line up.
    case value
    /// Paths, identifiers, keys, code and logs: monospaced.
    case code
    /// Explanations, footnotes and summaries that support what's around them.
    case secondary
}

public extension View {
    /// Sets the text in this view in one of the drawer's ``DebugDrawerTextStyle`` roles.
    ///
    /// In release it changes nothing, so a caller compiles unchanged.
    func debugDrawerFont(_ style: DebugDrawerTextStyle) -> some View {
        #if DEBUG
            font(style.font)
        #else
            self
        #endif
    }
}

#if DEBUG
    extension DebugDrawerTextStyle {
        /// The style's font on this platform.
        var font: Font {
            #if os(macOS)
                // The Mac's text styles: title3 15 pt, body 13, callout 12, subheadline 11.
                switch self {
                case .title: .callout.bold()
                case .heading: .subheadline.weight(.semibold)
                case .body: .body
                case .label: .subheadline
                case .value: .system(.subheadline, design: .monospaced).monospacedDigit()
                case .code: .system(.subheadline, design: .monospaced)
                case .secondary: .subheadline
                }
            #else
                switch self {
                case .title: .headline.bold()
                case .heading: .footnote.weight(.semibold)
                case .body: .body
                case .label: .footnote
                case .value: .system(.callout, design: .monospaced).monospacedDigit()
                case .code: .system(.footnote, design: .monospaced)
                case .secondary: .footnote
                }
            #endif
        }

        /// A value in words beside its label: the size of ``value`` in the system font, so a
        /// column of figures and words keeps one size.
        static var wordValue: Font {
            #if os(macOS)
                .subheadline
            #else
                .callout
            #endif
        }

        /// The drawer's own title, "Debug": a step above the plugins' titles.
        static var panelTitle: Font {
            #if os(macOS)
                .title3.bold()
            #else
                .title2.bold()
            #endif
        }
    }
#endif
