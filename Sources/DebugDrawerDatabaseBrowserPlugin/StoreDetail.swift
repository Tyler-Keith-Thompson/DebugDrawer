#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The selected store below the list, at the drawer's full width: its name with a close
    /// button, its path, what it is as inspector rows, then its tables, or for a Core Data store
    /// its entities and then Core Data's own tables. A store that can't be read says why.
    struct StoreDetail: View {
        let listing: StoreListing
        @Binding var selectedTable: StoreTable.ID?
        let onClose: () -> Void
        @Environment(\.locale) private var locale

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerRow(listing.store.name) {
                    DebugDrawerCodeText(listing.store.path)
                } accessory: {
                    Button(action: onClose) {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .debugDrawerButtonStyle(.borderless)
                    .accessibilityLabel("Close \(listing.store.name)")
                }
                facts
                if !listing.store.canWriteSharedMemory, listing.isReadable {
                    DebugDrawerIssueRow("Its -shm file is read-only", severity: .warning) {
                        Text("A WAL store is read through its -shm file. While it can't be written, a read may fail when the app writes.")
                    }
                }
                switch listing.schema {
                case let .failure(error):
                    DebugDrawerIssueRow(error.title, severity: .error) {
                        Text(error.explanation)
                    }
                case let .success(schema):
                    tables(of: schema)
                }
            }
        }

        private var facts: some View {
            let store = listing.store
            return VStack(alignment: .leading, spacing: 0) {
                if case let .success(schema) = listing.schema {
                    DebugDrawerKeyValueRow("Kind", value: schema.kind.title)
                        .debugDrawerValueStyle(.text)
                }
                DebugDrawerKeyValueRow("Folder", value: store.location.title)
                DebugDrawerKeyValueRow("Size", value: store.size.formatted(.byteCount(style: .file).locale(locale)))
                DebugDrawerKeyValueRow("Journal", value: store.journalMode.title)
                    .debugDrawerValueStyle(.text)
                if let walSize = store.walSize {
                    DebugDrawerKeyValueRow("WAL file", value: walSize.formatted(.byteCount(style: .file).locale(locale)))
                }
                if case let .success(schema) = listing.schema, case let .coreData(metadata) = schema.kind {
                    if let uuid = metadata.storeUUID {
                        DebugDrawerKeyValueRow("Store UUID", value: uuid)
                    }
                    if !metadata.versionIdentifiers.isEmpty {
                        DebugDrawerKeyValueRow("Model", value: metadata.versionIdentifiers.joined(separator: ", "))
                    }
                    if let digest = metadata.versionHashesDigest {
                        DebugDrawerKeyValueRow("Model hash", value: digest)
                    }
                }
            }
        }

        @ViewBuilder
        private func tables(of schema: StoreSchema) -> some View {
            if schema.tables.isEmpty {
                DebugDrawerSection("Tables") {
                    EmptyView()
                } footer: {
                    Text("The store has no tables yet.")
                }
            } else if case .coreData = schema.kind {
                DebugDrawerSection("Entities") {
                    rows(schema.entityTables)
                } footer: {
                    if schema.entityTables.isEmpty {
                        Text("Z_PRIMARYKEY names no entity with a table.")
                    }
                }
                if !schema.otherTables.isEmpty {
                    DebugDrawerSection("Core Data's tables") {
                        rows(schema.otherTables)
                    }
                }
            } else {
                DebugDrawerSection("Tables") {
                    rows(schema.tables)
                }
            }
        }

        private func rows(_ tables: [StoreTable]) -> some View {
            ForEach(tables) { table in
                TableRow(table: table, isSelected: selectedTable == table.id) {
                    selectedTable = selectedTable == table.id ? nil : table.id
                }
            }
        }
    }
#endif
