// Views render on the Mac; the snapshot packages are linked on Apple platforms only.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerDatabaseBrowserPlugin
    import Foundation
    import SnapshotTesting
    import SwiftUI
    import Testing

    // ImageRenderer draws AppKit-backed controls (the fields, the editor, the buttons) as
    // placeholders, so the tests host the view in a window that is never shown and draw it into a
    // bitmap at a fixed 2x scale, in the appearance the test asks for. macOS doesn't scale text
    // with Dynamic Type, so the Mac pins light and dark only. Sizes are drawn in en_US.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DatabaseBrowserSnapshotTests {
        @Test("Stores list with name, size, kind, journal, folder and path; one that can't be read says why in red",
              arguments: [ColorScheme.light, .dark])
        func stores(colorScheme: ColorScheme) throws {
            let shop = DatabaseStore(
                url: URL(filePath: "/Users/me/Library/Containers/com.example.shop/Data/Library/Application Support/Sample Shop.sqlite"),
                location: .applicationSupport, size: 98_304, walSize: 4_152, journalMode: .wal, canWriteSharedMemory: true
            )
            let tables = [
                StoreTable(
                    name: "products", isView: false,
                    columns: [
                        StoreColumn(name: "id", declaredType: "INTEGER"), StoreColumn(name: "name", declaredType: "TEXT"),
                        StoreColumn(name: "price", declaredType: "REAL"), StoreColumn(name: "notes", declaredType: "TEXT"),
                        StoreColumn(name: "thumbnail", declaredType: "BLOB")
                    ],
                    rowCount: 120, hasRowID: true
                ),
                StoreTable(name: "customers", isView: false, columns: [], rowCount: 60, hasRowID: true),
                StoreTable(name: "orders", isView: false, columns: [], rowCount: 300, hasRowID: true),
                StoreTable(name: "big_spenders", isView: true, columns: [], rowCount: 7, hasRowID: false)
            ]
            let listing = StoreListing(store: shop, schema: .success(StoreSchema(kind: .sqlite, tables: tables)))
            let notes = StoreListing(
                store: DatabaseStore(
                    url: URL(filePath: "/Users/me/Library/Containers/com.example.shop/Data/Library/Application Support/default.store"),
                    location: .applicationSupport, size: 45_056, walSize: 0, journalMode: .wal, canWriteSharedMemory: true
                ),
                schema: .success(StoreSchema(kind: .coreData(CoreDataMetadata()), tables: []))
            )
            let broken = StoreListing(
                store: DatabaseStore(
                    url: URL(filePath: "/Users/me/Library/Containers/com.example.shop/Data/Documents/cache.db"),
                    location: .documents, size: 100, walSize: nil, journalMode: .rollback, canWriteSharedMemory: true
                ),
                schema: .failure(.notADatabase)
            )
            let sut = DatabaseBrowserView(
                stores: .loaded([listing, notes, broken]), filter: .constant(""), selectedStore: .constant(nil), selectedTable: .constant(nil),
                search: .constant(""), page: .loading, sql: .constant(""), query: .idle, actions: DatabaseBrowserActions()
            )
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A selected table pages its rows in a grid: NULL, integers, reals, text and blobs each drawn their own way",
              arguments: [ColorScheme.light, .dark])
        func rows(colorScheme: ColorScheme) throws {
            let shop = DatabaseStore(
                url: URL(filePath: "/Users/me/Library/Containers/com.example.shop/Data/Library/Application Support/Sample Shop.sqlite"),
                location: .applicationSupport, size: 98_304, walSize: 4_152, journalMode: .wal, canWriteSharedMemory: true
            )
            let tables = [
                StoreTable(
                    name: "products", isView: false,
                    columns: [
                        StoreColumn(name: "id", declaredType: "INTEGER"), StoreColumn(name: "name", declaredType: "TEXT"),
                        StoreColumn(name: "price", declaredType: "REAL"), StoreColumn(name: "notes", declaredType: "TEXT"),
                        StoreColumn(name: "thumbnail", declaredType: "BLOB")
                    ],
                    rowCount: 120, hasRowID: true
                ),
                StoreTable(name: "customers", isView: false, columns: [], rowCount: 60, hasRowID: true),
                StoreTable(name: "orders", isView: false, columns: [], rowCount: 300, hasRowID: true),
                StoreTable(name: "big_spenders", isView: true, columns: [], rowCount: 7, hasRowID: false)
            ]
            let listing = StoreListing(store: shop, schema: .success(StoreSchema(kind: .sqlite, tables: tables)))
            let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A])
            let page = TablePage(
                rows: ResultSet(columns: ["id", "name", "price", "notes", "thumbnail"], rows: [
                    [.integer(1), .text("Espresso cup"), .real(9.5), .null, .blob(size: 2_048, prefix: png)],
                    [.integer(2), .text("A very long product name that goes on past forty characters"), .real(12), .text("Gift"), .null],
                    [.integer(3), .text("Plate"), .real(0.25), .text("Line one\nline two"), .blob(size: 0, prefix: Data())]
                ]),
                pageIndex: 0, matchingCount: 120, searchedColumns: []
            )
            let sut = DatabaseBrowserView(
                stores: .loaded([listing]), filter: .constant(""), selectedStore: .constant(shop.id), selectedTable: .constant("products"),
                search: .constant(""), page: .loaded(page), sql: .constant(""), query: .idle, actions: DatabaseBrowserActions()
            )
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("The grid draws each storage class its own way, cut cells ending in an ellipsis, and notes when the read was cut",
              arguments: [ColorScheme.light, .dark])
        func cells(colorScheme: ColorScheme) throws {
            let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52])
            let result = ResultSet(columns: ["id", "name", "price", "notes", "thumbnail"], rows: [
                [.integer(1), .text("Espresso cup"), .real(9.5), .null, .blob(size: 2_048, prefix: png)],
                [.integer(2), .text("A very long product name that goes on"), .real(12), .text("Gift"), .null],
                [.integer(-3), .text("Plate"), .real(0.25), .text("Line one\nline two"), .blob(size: 0, prefix: Data())]
            ], isTruncated: true)
            let sut = ResultGrid(result: result)
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 640, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A Core Data or SwiftData store lists its entities by name over their tables, then Core Data's own, and its model",
              arguments: [ColorScheme.light, .dark])
        func coreData(colorScheme: ColorScheme) throws {
            let store = DatabaseStore(
                url: URL(filePath: "/Users/me/Library/Application Support/default.store"),
                location: .applicationSupport, size: 45_056, walSize: 32_992, journalMode: .wal, canWriteSharedMemory: true
            )
            let tables = [
                StoreTable(
                    name: "ZANIMAL", isView: false, columns: [], rowCount: 9, hasRowID: true,
                    entity: CoreDataEntityTable(name: "Animal", subentities: ["Cat", "Dog"])
                ),
                StoreTable(
                    name: "ZNOTE", isView: false, columns: [], rowCount: 12, hasRowID: true,
                    entity: CoreDataEntityTable(name: "Note", subentities: [])
                ),
                StoreTable(name: "Z_METADATA", isView: false, columns: [], rowCount: 1, hasRowID: true),
                StoreTable(name: "Z_MODELCACHE", isView: false, columns: [], rowCount: 1, hasRowID: true),
                StoreTable(name: "Z_PRIMARYKEY", isView: false, columns: [], rowCount: 4, hasRowID: true)
            ]
            let metadata = CoreDataMetadata(
                storeUUID: "6F1C2B8E-2E5B-4C7F-9A41-0E2D7D9B5A10", versionIdentifiers: [],
                versionHashesDigest: "pF0g3K9vXk1yYc0a2cQ2bTq8l1t3mJzqk8yq1b7a0Zo="
            )
            let listing = StoreListing(store: store, schema: .success(StoreSchema(kind: .coreData(metadata), tables: tables)))
            let sut = DatabaseBrowserView(
                stores: .loaded([listing]), filter: .constant(""), selectedStore: .constant(store.id), selectedTable: .constant(nil),
                search: .constant(""), page: .loading, sql: .constant(""), query: .idle, actions: DatabaseBrowserActions()
            )
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A refused query shows inline as an issue row under the editor", arguments: [ColorScheme.light, .dark])
        func refusedQuery(colorScheme: ColorScheme) throws {
            let sut = QuerySection(sql: .constant("INSERT INTO products(name) VALUES ('Mug')"), state: .failed(.writes)) {}
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }

        @Test("A finished query shows its result in the grid with Copy Result as CSV", arguments: [ColorScheme.light, .dark])
        func finishedQuery(colorScheme: ColorScheme) throws {
            let result = ResultSet(columns: ["name", "orders", "total"], rows: [
                [.text("Ana"), .integer(12), .real(301.5)], [.text("Bo"), .integer(3), .real(44)], [.text("Chen"), .integer(0), .null]
            ])
            let sql = "SELECT c.name, count(o.id) AS orders, sum(o.total) AS total\nFROM customers c\n"
                + "LEFT JOIN orders o ON o.customer_id = c.id\nGROUP BY c.id"
            let sut = QuerySection(sql: .constant(sql), state: .finished(result)) {}
            let host = NSHostingView(rootView: sut
                .environment(\.locale, Locale(identifier: "en_US"))
                .frame(width: 320, alignment: .leading)
                .padding()
                .background(.background))
            host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
            let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
            window.contentView = host
            host.frame = CGRect(origin: .zero, size: host.fittingSize)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(host.bounds.width) * 2, pixelsHigh: Int(host.bounds.height) * 2,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
            ))
            bitmap.size = host.bounds.size
            host.cacheDisplay(in: host.bounds, to: bitmap)

            let actual = NSImage(size: host.bounds.size)
            actual.addRepresentation(bitmap)

            assertSnapshot(of: actual, as: .image(perceptualPrecision: 0.98), named: "\(colorScheme)")
        }
    }
#endif
