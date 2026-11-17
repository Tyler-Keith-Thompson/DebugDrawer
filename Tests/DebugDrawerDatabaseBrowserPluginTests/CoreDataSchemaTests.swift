@testable import DebugDrawerDatabaseBrowserPlugin
import Foundation
import SQLite3
import Testing

@Suite(.timeLimit(.minutes(1)))
struct CoreDataSchemaTests {
    @Test("A store with Z_METADATA and Z_PRIMARYKEY is Core Data's: tables named by entity, subentities under their root, metadata read")
    func craftedStore() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Model.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        let setup = """
        CREATE TABLE Z_PRIMARYKEY (Z_ENT INTEGER PRIMARY KEY, Z_NAME VARCHAR, Z_SUPER INTEGER, Z_MAX INTEGER);
        CREATE TABLE Z_METADATA (Z_VERSION INTEGER PRIMARY KEY, Z_UUID VARCHAR(255), Z_PLIST BLOB);
        CREATE TABLE Z_MODELCACHE (Z_CONTENT BLOB);
        CREATE TABLE ZORDER (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZTOTAL FLOAT, ZNOTE VARCHAR);
        CREATE TABLE ZANIMAL (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, Z_OPT INTEGER, ZNAME VARCHAR);
        CREATE TABLE Z_2TAGS (Z_2ORDERS INTEGER, Z_3TAGS INTEGER);
        INSERT INTO Z_PRIMARYKEY VALUES (1, 'Animal', 0, 3), (2, 'Order', 0, 2), (3, 'Dog', 1, 1), (4, 'Cat', 1, 2), (5, 'Tag', 0, 0);
        INSERT INTO ZORDER VALUES (1, 2, 1, 9.5, 'first'), (2, 2, 1, 12.25, NULL);
        INSERT INTO ZANIMAL VALUES (1, 3, 1, 'Rex'), (2, 4, 1, 'Tom'), (3, 4, 1, 'Felix');
        """
        try #require(sqlite3_exec(writer, setup, nil, nil, nil) == SQLITE_OK)
        let plist = try PropertyListSerialization.data(fromPropertyList: [
            "NSStoreModelVersionIdentifiers": ["v3", ""],
            "NSStoreModelVersionHashesDigest": "q9Lx0dQ1nRkQ==",
            "NSStoreType": "SQLite"
        ], format: .binary, options: 0)
        var statement: OpaquePointer?
        try #require(sqlite3_prepare_v2(writer, "INSERT INTO Z_METADATA VALUES (1, 'B1E2-UUID', ?)", -1, &statement, nil) == SQLITE_OK)
        // Bound without a copy, so it is stepped while the bytes are still lent.
        let stepped = plist.withUnsafeBytes { bytes in
            sqlite3_bind_blob(statement, 1, bytes.baseAddress, Int32(plist.count), nil)
            return sqlite3_step(statement)
        }
        try #require(stepped == SQLITE_DONE)
        sqlite3_finalize(statement)
        let expectedMetadata = CoreDataMetadata(storeUUID: "B1E2-UUID", versionIdentifiers: ["v3"], versionHashesDigest: "q9Lx0dQ1nRkQ==")
        let expectedEntities = ["Animal", "Order"]
        let expectedOthers = ["Z_2TAGS", "Z_METADATA", "Z_MODELCACHE", "Z_PRIMARYKEY"]

        let actual = try await SQLiteStore(url: url).schema()

        #expect(actual.kind == .coreData(expectedMetadata))
        #expect(actual.kind.title == "Core Data / SwiftData")
        #expect(actual.entityTables.map(\.displayName) == expectedEntities)
        #expect(actual.entityTables.map(\.name) == ["ZANIMAL", "ZORDER"])
        #expect(actual.entityTables.map(\.rowCount) == [3, 2])
        #expect(actual.entityTables.first?.entity?.subentities == ["Cat", "Dog"])
        #expect(actual.otherTables.map(\.name) == expectedOthers)
        #expect(actual.entityTables.first?.detail == "ZANIMAL · also Cat, Dog")
    }

    @Test("A store with only one of Core Data's tables is plain SQLite, its tables by name")
    func plainSQLite() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "Plain.sqlite")
        var writer: OpaquePointer?
        try #require(sqlite3_open(url.path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        let setup = "CREATE TABLE Z_METADATA (Z_VERSION INTEGER); CREATE TABLE zebra (id INTEGER); CREATE VIEW recent AS SELECT * FROM zebra;"
        try #require(sqlite3_exec(writer, setup, nil, nil, nil) == SQLITE_OK)

        let actual = try await SQLiteStore(url: url).schema()

        #expect(actual.kind == .sqlite)
        #expect(actual.tables.map(\.displayName) == ["Z_METADATA", "recent", "zebra"])
        #expect(actual.tables.map(\.isView) == [false, true, false])
        #expect(actual.entityTables.isEmpty)
        #expect(actual.tables[1].hasRowID == false)
        #expect(actual.tables[1].detail == "view")
    }

    @Test("Entities map to Z plus their root's name in capitals; a loop or a missing parent stops at the break")
    func entityMapping() {
        let entities = [
            CoreDataSchema.Entity(id: 1, name: "Item", superID: 0),
            CoreDataSchema.Entity(id: 2, name: "Book", superID: 1),
            CoreDataSchema.Entity(id: 3, name: "Ebook", superID: 2),
            CoreDataSchema.Entity(id: 4, name: "Orphan", superID: 99),
            CoreDataSchema.Entity(id: 5, name: "Loop", superID: 6),
            CoreDataSchema.Entity(id: 6, name: "Pool", superID: 5)
        ]

        let actual = CoreDataSchema.entityTables(entities)

        #expect(actual["ZITEM"] == CoreDataEntityTable(name: "Item", subentities: ["Book", "Ebook"]))
        #expect(actual["ZORPHAN"] == CoreDataEntityTable(name: "Orphan", subentities: []))
        #expect(actual.count == 4)
        #expect(CoreDataSchema.entityTables([]).isEmpty)
    }

    @Test("Metadata with no property list keeps the UUID; a property list's UUID fills in for a missing column")
    func metadataFallbacks() throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: ["NSStoreUUID": "FROM-PLIST"], format: .xml, options: 0)

        let withoutPlist = CoreDataSchema.metadata(uuid: "COLUMN", plist: nil)
        let fromPlist = CoreDataSchema.metadata(uuid: nil, plist: plist)
        let garbage = CoreDataSchema.metadata(uuid: nil, plist: Data("nope".utf8))

        #expect(withoutPlist == CoreDataMetadata(storeUUID: "COLUMN"))
        #expect(fromPlist == CoreDataMetadata(storeUUID: "FROM-PLIST"))
        #expect(garbage == CoreDataMetadata())
    }
}
