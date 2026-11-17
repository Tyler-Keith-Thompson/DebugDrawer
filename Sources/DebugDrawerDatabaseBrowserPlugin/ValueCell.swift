#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One value in the grid, on one line in code type, each storage class drawn its own way:
    /// NULL as the word in the tertiary color and italics, numbers in the accent color against the
    /// column's trailing edge, text as it is, a blob's size and first bytes in the secondary color.
    struct ValueCell: View {
        let value: SQLiteValue
        /// The most characters shown before the text is cut with an ellipsis.
        static let characterLimit = 24

        var body: some View {
            text
                .debugDrawerFont(.code)
                .debugDrawerForegroundStyle(foregroundStyle)
                // One line at any text size: the grid scrolls sideways, and cellText already cut it.
                .fixedSize(horizontal: true, vertical: false)
                .frame(maxWidth: .infinity, alignment: isNumber ? .trailing : .leading)
        }

        /// The value's text; NULL's in italics, so it reads apart from the text "NULL".
        private var text: Text {
            let text = Text(value.cellText(limit: Self.characterLimit))
            return value == .null ? text.italic() : text
        }

        /// The color the value is drawn in.
        var foregroundStyle: DebugDrawerForegroundStyle {
            switch value {
            case .null: .tertiary
            case .integer, .real: .accent
            case .text: .primary
            case .blob: .secondary
            }
        }

        /// Whether the value is a number, which lines up against the column's trailing edge.
        var isNumber: Bool {
            switch value {
            case .integer, .real: true
            case .null, .text, .blob: false
            }
        }
    }
#endif
