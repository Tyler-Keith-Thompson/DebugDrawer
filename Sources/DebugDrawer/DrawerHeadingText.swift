#if DEBUG
    import SwiftUI

    /// The name of a group of rows inside a plugin, in sentence case and the secondary text color,
    /// read by VoiceOver as a heading.
    struct DrawerHeadingText: View {
        let title: String

        init(_ title: String) {
            self.title = title
        }

        var body: some View {
            Text(title)
                .debugDrawerFont(.heading)
                .foregroundStyle(DrawerPalette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        }
    }
#endif
