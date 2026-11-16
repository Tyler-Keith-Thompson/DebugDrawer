#if DEBUG
    import SwiftUI

    /// The button in the drawer's header that closes it.
    struct DrawerCloseButton: View {
        /// The smallest tap target Apple's Human Interface Guidelines allow.
        static let minimumTapSize: CGFloat = 44

        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                    // A plain-style button is hit only where it draws, so the glyph alone would be
                    // a target too small to tap reliably.
                    .frame(minWidth: Self.minimumTapSize, minHeight: Self.minimumTapSize)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close the debug drawer")
        }
    }
#endif
