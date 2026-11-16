#if DEBUG
    import SwiftUI

    /// A hairline one device pixel thick, so it is crisp at every scale: under the header block,
    /// under each plugin and above the filter bar.
    struct DrawerRule: View {
        @Environment(\.displayScale) private var displayScale

        var body: some View {
            Rectangle()
                .fill(DrawerPalette.separator)
                .frame(height: 1 / displayScale)
                .accessibilityHidden(true)
        }
    }

    extension EnvironmentValues {
        /// Whether the view sits inside a row, where an action row sits closer to the row's text.
        @Entry var isInDrawerRow = false
    }
#endif
