import CoreGraphics

/// The drawer's measures at the default text size, in points; each view scales the ones beside
/// text with `@ScaledMetric`. iOS is laid out for touch, with 44 pt targets; the Mac is compact,
/// as Xcode's panes are, since a pointer needs no such target.
enum DrawerSpacing {
    /// The panel's content from its leading and trailing edges.
    static let panelInset: CGFloat = isCompact ? 8 : 12
    /// A header icon button's hit area, square.
    static let iconButton: CGFloat = isCompact ? 22 : 44
    /// The jump bar's height and corners.
    static let jumpBarHeight: CGFloat = isCompact ? 22 : 34
    static let jumpBarRadius: CGFloat = 6
    /// A navigator tab's height and corners.
    static let tabHeight: CGFloat = isCompact ? 24 : 44
    static let tabRadius: CGFloat = 5
    /// The unread dot on a tab, and the panel-colored ring around it.
    static let unreadDot: CGFloat = 7
    static let unreadRing: CGFloat = 1.5
    /// A plugin's header row: its least height, and the disclosure triangle's size.
    static let sectionHeaderHeight: CGFloat = isCompact ? 24 : 44
    static let disclosure: CGFloat = isCompact ? 9 : 12
    /// How far a plugin's content is set in, past the disclosure triangle.
    static let contentIndent: CGFloat = isCompact ? 22 : 30
    /// The filter field's height and corners, and those of other text fields.
    static let fieldHeight: CGFloat = isCompact ? 22 : 36
    static let fieldRadius: CGFloat = 6
    /// Above and below a row's text.
    static let rowPadding: CGFloat = isCompact ? 3 : 6
    /// Between the parts of a row or a header: glyph, title, accessory.
    static let itemGap: CGFloat = isCompact ? 6 : 8
    /// An inspector form row's label column.
    static let formLabelWidth: CGFloat = isCompact ? 82 : 96
    /// A gauge row's label column, and its bar's height and corners.
    static let gaugeLabelWidth: CGFloat = isCompact ? 64 : 92
    static let gaugeHeight: CGFloat = isCompact ? 5 : 6
    static let gaugeRadius: CGFloat = 2
    /// A gauge row's value column, so the bars above and below end together.
    static let gaugeValueWidth: CGFloat = isCompact ? 64 : 84
    /// An issue glyph, a stack frame's badge and a type badge, square, and the badges' corners.
    static let glyph: CGFloat = isCompact ? 14 : 18
    static let badgeRadius: CGFloat = 3
    /// A count's capsule: its padding across.
    static let countPadding: CGFloat = isCompact ? 5 : 6
    /// A push button's least height, its title's padding across, and its corners.
    static let buttonHeight: CGFloat = isCompact ? 22 : 36
    static let buttonPadding: CGFloat = isCompact ? 10 : 14
    static let buttonRadius: CGFloat = 5
    /// Between the buttons of an action row.
    static let actionGap: CGFloat = isCompact ? 6 : 8
    /// A code block's corners and padding.
    static let codeRadius: CGFloat = isCompact ? 5 : 6
    static let codePadding: CGFloat = isCompact ? 6 : 8

    private static var isCompact: Bool {
        #if os(macOS)
            true
        #else
            false
        #endif
    }
}
