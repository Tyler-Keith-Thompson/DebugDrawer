#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A keychain item's title (a password's account, a certificate's or key's label), its service
    /// and its class; open, its detail below.
    struct KeychainRow: View {
        let item: KeychainItem
        /// The open item's detail; `nil` while the row is closed.
        let detail: KeychainSelection?
        let redaction: DebugDrawerRedaction
        let onSelect: () -> Void
        /// Opens the form on the item; `nil` for an item that can't be edited.
        var onEdit: (() -> Void)?
        let onDelete: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        private var isSelected: Bool {
            detail != nil
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onSelect) {
                    summary
                }
                .debugDrawerButtonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])

                if let detail {
                    KeychainItemDetail(selection: detail, redaction: redaction, onEdit: onEdit, onDelete: onDelete)
                }
            }
        }

        // The title and service in the drawer's code type, the item's class after them in
        // tertiary text; at accessibility text sizes the class sits below them. Each keeps to one
        // line cut in the middle, as the UserDefaults keys do, until the item is selected.
        private var summary: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(spacing: 6))
            return layout {
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title)
                        .debugDrawerFont(.code)
                        .debugDrawerForegroundStyle(.primary)
                        .lineLimit(isSelected ? nil : 1)
                        .truncationMode(.middle)
                        .help(item.title)
                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .debugDrawerFont(.code)
                            .debugDrawerForegroundStyle(.tertiary)
                            .lineLimit(isSelected ? nil : 1)
                            .truncationMode(.middle)
                            .help(subtitle)
                    }
                }

                if !dynamicTypeSize.isAccessibilitySize {
                    Spacer()
                }

                Text(item.itemClass.title)
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .debugDrawerRowPadding()
            .contentShape(Rectangle())
        }
    }
#endif
