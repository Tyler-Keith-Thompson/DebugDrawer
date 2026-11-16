#if DEBUG
    import SwiftUI

    /// The title above a group of plugins in the drawer: Local, Pinned or a category.
    struct DrawerSectionHeader: View {
        let title: String

        var body: some View {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .textCase(.uppercase)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 4)
        }
    }
#endif
