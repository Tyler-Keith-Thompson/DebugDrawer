@testable import DebugDrawer
@testable import DebugDrawerDatabaseBrowserPlugin
import Foundation
import SQLite3
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct DatabaseBrowserModelTests {
    @Test("Refresh lists every store found with its schema, or why it couldn't be read; pages and queries run on the store")
    func refresh() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var writer: OpaquePointer?
        try #require(sqlite3_open(folder.appending(path: "shop.sqlite").path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        let setup = "CREATE TABLE products(id INTEGER PRIMARY KEY, name TEXT); INSERT INTO products VALUES (1, 'Mug');"
        try #require(sqlite3_exec(writer, setup, nil, nil, nil) == SQLITE_OK)
        let broken = Data("SQLite format 3\0".utf8) + Data(count: 84)
        try #require(FileManager.default.createFile(atPath: folder.appending(path: "broken.db").path(percentEncoded: false), contents: broken))
        let discovery = StoreDiscovery(locations: FakeStoreLocations(applicationSupport: folder), additionalDirectories: [])
        let sut = DatabaseBrowserModel(discovery: discovery)
        #expect(sut.stores == .loading)

        await sut.refresh()

        let listings = sut.listings
        #expect(listings.map(\.store.name) == ["broken.db", "shop.sqlite"])
        #expect(listings[0].schema == .failure(.notADatabase))
        let schema = try listings[1].schema.get()
        #expect(schema.tables.map(\.name) == ["products"])
        let page = await sut.page(TablePageRequest(table: schema.tables[0]), of: listings[1].store)
        let query = await sut.run("SELECT name FROM products", on: listings[1].store)
        let refused = await sut.run("DELETE FROM products", on: listings[1].store)
        #expect(page == .loaded(TablePage(
            rows: ResultSet(columns: ["id", "name"], rows: [[.integer(1), .text("Mug")]]), pageIndex: 0, matchingCount: 1, searchedColumns: []
        )))
        #expect(query == .finished(ResultSet(columns: ["name"], rows: [[.text("Mug")]])))
        guard case .failed(.refused) = refused else {
            Issue.record("Expected the delete to be refused, got \(refused)")
            return
        }
    }

    @Test("A store that went away fails its page with an error rather than showing stale rows")
    func storeGone() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "gone.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        try #require(sqlite3_exec(writer, "CREATE TABLE t(id INTEGER PRIMARY KEY)", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(writer)
        let sut = DatabaseBrowserModel(discovery: StoreDiscovery(locations: FakeStoreLocations(documents: folder), additionalDirectories: []))
        await sut.refresh()
        let listing = try #require(sut.listings.first)
        try FileManager.default.removeItem(at: url)

        let actual = await sut.page(TablePageRequest(table: try listing.schema.get().tables[0]), of: listing.store)

        guard case .failed(.cannotOpen) = actual else {
            Issue.record("Expected the read to fail, got \(actual)")
            return
        }
    }

    @Test("databases.txt lists each store's path, folder, size, journal, kind and tables with row counts, and no row")
    func report() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "shop.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        let setup = "PRAGMA journal_mode = DELETE; CREATE TABLE products(id INTEGER PRIMARY KEY, name TEXT); "
            + "INSERT INTO products VALUES (1, 'secret-sku');"
        try #require(sqlite3_exec(writer, setup, nil, nil, nil) == SQLITE_OK)
        let discovery = StoreDiscovery(locations: FakeStoreLocations(applicationSupport: folder), additionalDirectories: [])
        let model = DatabaseBrowserModel(discovery: discovery)
        var empty = DebugDrawerReport()
        DatabaseBrowserPlugin.contribute(model.stores, to: &empty)
        await model.refresh()
        var sut = DebugDrawerReport()

        DatabaseBrowserPlugin(model: model).contribute(to: &sut, redaction: .standard)

        let file = try #require(sut.files.first)
        let emptyFile = try #require(empty.files.first)
        let text = try #require(String(bytes: file.data, encoding: .utf8))
        let path = try #require(model.listings.first).store.path
        let lines = text.components(separatedBy: "\n")
        #expect(sut.files.map(\.name) == ["databases.txt"])
        #expect(lines.first == "Stores (1):")
        #expect(lines.contains("  \(path)"))
        #expect(lines.contains("    folder: Application Support"))
        #expect(lines.contains("    journal: Rollback journal"))
        #expect(lines.contains("    kind: SQLite"))
        #expect(lines.contains("      products: 1 row"))
        #expect(!text.contains("secret-sku"))
        #expect(String(bytes: emptyFile.data, encoding: .utf8) == "Stores: not read yet")
    }
}
