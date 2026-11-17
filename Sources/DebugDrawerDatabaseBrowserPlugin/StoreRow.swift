#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A store in the list: its file name and size, what it is (kind, journal, folder), and its
    /// path on one line cut in the middle. Selected, it is drawn on the selection fill, and its
    /// tables show below the list (``StoreDetail``).
    struct StoreRow: View {
        let listing: StoreListing
        let isSelected: Bool
        let onToggle: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.locale) private var locale

        var body: some View {
            Button(action: onToggle) {
                VStack(alignment: .leading, spacing: 2) {
                    rowLayout {
                        Text(listing.store.name)
                            .debugDrawerFont(.body)
                            .debugDrawerForegroundStyle(.primary)
                            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                            .truncationMode(.middle)
                            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
                        Text(listing.store.size.formatted(.byteCount(style: .file).locale(locale)))
                            .debugDrawerFont(.value)
                            .debugDrawerForegroundStyle(.tertiary)
                    }
                    Text(listing.summary)
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(listing.isReadable ? .secondary : .error)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(listing.store.path)
                        .debugDrawerFont(.code)
                        .debugDrawerForegroundStyle(.tertiary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .truncationMode(.middle)
                        .help(listing.store.path)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .debugDrawerRowPadding()
                .debugDrawerSelected(isSelected)
                .contentShape(Rectangle())
            }
            .debugDrawerButtonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(isSelected ? "Hides its tables" : "Shows its tables below the list")
        }

        // At accessibility sizes the size goes below the name, so the name keeps the width.
        private var rowLayout: AnyLayout {
            dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        }
    }

    extension StoreListing {
        /// What the store is, in a line: "SQLite · WAL · Application Support", or why it can't be
        /// read.
        var summary: String {
            switch schema {
            case let .success(schema):
                [schema.kind.title, store.journalMode.title, store.location.title].joined(separator: " · ")
            case let .failure(error):
                "\(error.title) · \(store.location.title)"
            }
        }

        /// Whether its schema was read.
        var isReadable: Bool {
            if case .success = schema { true } else { false }
        }

        /// Whether the filter's text appears in its name, path, folder, kind or a table's or
        /// entity's name, ignoring case and diacritics; blank text matches every store.
        func matches(_ query: String) -> Bool {
            let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !query.isEmpty else { return true }
            let tables = (try? schema.get().tables.flatMap { [$0.name, $0.entity?.name].compactMap(\.self) }) ?? []
            return ([store.path, summary] + tables).contains {
                $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }
#endif
