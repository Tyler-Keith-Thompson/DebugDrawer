import SwiftUI

public extension View {
    /// Gives the text fields in this view the drawer's look: plain text on a light field with a
    /// hairline edge, as tall as a button. On tvOS and watchOS the field keeps the system's look,
    /// since it edits in a full-screen keyboard (or dictation and Scribble on the watch).
    ///
    /// In release it changes nothing, so a caller compiles unchanged.
    @ViewBuilder
    func debugDrawerTextFieldStyle() -> some View {
        #if DEBUG && !os(tvOS) && !os(watchOS)
            modifier(DrawerTextFieldStyle(systemImage: nil))
        #else
            self
        #endif
    }
}

#if DEBUG && !os(tvOS) && !os(watchOS)
    extension View {
        /// The drawer's text field look with a symbol before the text, as the filter field's
        /// funnel.
        func drawerTextFieldStyle(systemImage: String) -> some View {
            modifier(DrawerTextFieldStyle(systemImage: systemImage))
        }
    }

    /// The look `debugDrawerTextFieldStyle()` gives a text field.
    struct DrawerTextFieldStyle: ViewModifier {
        let systemImage: String?
        @ScaledMetric(relativeTo: .body) private var height = DrawerSpacing.fieldHeight
        @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.itemGap
        @ScaledMetric(relativeTo: .body) private var radius = DrawerSpacing.fieldRadius
        @Environment(\.displayScale) private var displayScale

        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: radius)
            HStack(spacing: padding / 2) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(DrawerPalette.tertiaryText)
                        .accessibilityHidden(true)
                }
                content
                    .textFieldStyle(.plain)
                    .foregroundStyle(DrawerPalette.text)
            }
            .debugDrawerFont(.body)
            .padding(.horizontal, padding)
            // A fixed height, not a least one: AppKit's field sometimes reports itself 3 points
            // taller from one layout to the next, which moved every row below it. The height grows
            // with the text, as the field's line does.
            .frame(height: height)
            .background(DrawerPalette.field, in: shape)
            .overlay { shape.strokeBorder(DrawerPalette.separator, lineWidth: 1 / displayScale) }
        }
    }
#endif
