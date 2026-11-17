#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A table in a store's list: its name, or for a Core Data entity table the entity's name with
    /// the table's below, and its row count. Selected, it is drawn on the selection fill and its
    /// rows show below.
    struct TableRow: View {
        let table: StoreTable
        let isSelected: Bool
        let onToggle: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        // The selection fill reaches this far past the text on each side, so the names line up
        // with the section title above while the fill still frames them.
        @ScaledMetric(relativeTo: .body) private var fillInset: CGFloat = 6

        var body: some View {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 2) {
                    rowLayout {
                        Text(table.displayName)
                            .debugDrawerFont(.body)
                            .debugDrawerForegroundStyle(.primary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .truncationMode(.middle)
                            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
                        Text(table.rowCountText)
                            .debugDrawerFont(.value)
                            .debugDrawerForegroundStyle(.tertiary)
                    }
                    if let detail = table.detail {
                        Text(detail)
                            .debugDrawerFont(.code)
                            .debugDrawerForegroundStyle(.tertiary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .truncationMode(.middle)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .debugDrawerRowPadding()
                .padding(.horizontal, fillInset)
                .debugDrawerSelected(isSelected)
                .padding(.horizontal, -fillInset)
                .contentShape(Rectangle())
            }
            .debugDrawerButtonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(isSelected ? "Hides its rows" : "Shows its rows below")
        }

        // At accessibility sizes the count goes below the name, so the name keeps the width.
        private var rowLayout: AnyLayout {
            dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        }
    }

    extension StoreTable {
        /// "312 rows", "1 row", or "?" when counting failed.
        var rowCountText: String {
            guard let rowCount else { return "?" }
            return rowCount == 1 ? "1 row" : "\(rowCount.formatted()) rows"
        }

        /// The line below the name: an entity table's raw name and its subentities, or "view".
        var detail: String? {
            if let entity {
                return ([name] + (entity.subentities.isEmpty ? [] : ["also " + entity.subentities.joined(separator: ", ")]))
                    .joined(separator: " · ")
            }
            return isView ? "view" : nil
        }
    }
#endif
