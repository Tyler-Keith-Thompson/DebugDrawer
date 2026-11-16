#if DEBUG
    import SwiftUI

    /// The button in the drawer's header that closes it.
    struct DrawerCloseButton: View {
        /// The smallest tap target Apple's Human Interface Guidelines allow.
        static let minimumTapSize: CGFloat = 44
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                DrawerIconButtonLabel(systemImage: "xmark")
            }
            .debugDrawerButtonStyle(.plain)
            .accessibilityLabel("Close the debug drawer")
        }
    }

    /// The face of one of the header's icon buttons: a plain symbol in the secondary color, in a
    /// square hit area of 44 points on iOS and 22 on the Mac, as Xcode's pane buttons are.
    struct DrawerIconButtonLabel: View {
        let systemImage: String
        @ScaledMetric(relativeTo: .body) private var size = DrawerSpacing.iconButton

        var body: some View {
            Image(systemName: systemImage)
                .debugDrawerFont(.body)
                .foregroundStyle(DrawerPalette.secondaryText)
                .frame(minWidth: size, minHeight: size)
                .contentShape(Rectangle())
                .accessibilityHidden(true)
        }
    }
#endif
