@testable import DebugDrawerDatabaseBrowserPlugin
import Foundation
import SQLite3
import Testing

@Suite
struct StoreDiscoveryTests {
    @Test("Stores are found in Application Support, Documents and each app group's container, at any depth, in that order")
    func threeLocations() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let support = folder.appending(path: "Application Support", directoryHint: .isDirectory)
        let documents = folder.appending(path: "Documents", directoryHint: .isDirectory)
        let group = folder.appending(path: "Group", directoryHint: .isDirectory)
        for directory in [support.appending(path: "Model"), documents, group.appending(path: "Library/Shared")] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let files = [
            support.appending(path: "Model/Cache.sqlite"), documents.appending(path: "notes.db"),
            group.appending(path: "Library/Shared/shared.sqlite3")
        ]
        for file in files {
            try #require(FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: Data()))
        }
        let locations = FakeStoreLocations(
            applicationSupport: support, documents: documents,
            appGroupIdentifiers: ["group.com.example.shared", "group.com.example.none"],
            appGroupContainers: ["group.com.example.shared": group]
        )
        let sut = StoreDiscovery(locations: locations, additionalDirectories: [])
        let expected: [String] = ["Cache.sqlite", "notes.db", "shared.sqlite3"]
        let expectedLocations: [StoreLocation] = [.applicationSupport, .documents, .appGroup("group.com.example.shared")]

        let actual = sut.stores()

        #expect(actual.map(\.name) == expected)
        #expect(actual.map(\.location) == expectedLocations)
    }

    @Test("A store's -wal, -shm and -journal files aren't stores; other extensions and files that aren't SQLite are skipped")
    func sidecarsAndExtensions() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var writer: OpaquePointer?
        try #require(sqlite3_open(folder.appending(path: "Orders.sqlite").path(percentEncoded: false), &writer) == SQLITE_OK)
        defer { sqlite3_close(writer) }
        try #require(sqlite3_exec(writer, "PRAGMA journal_mode = WAL; CREATE TABLE orders(id INTEGER PRIMARY KEY);", nil, nil, nil) == SQLITE_OK)
        let others: [(String, Data)] = [
            ("Orders.sqlite-journal", Data()), ("default.store", Data("SQLite format 3\0".utf8) + Data(count: 84)),
            ("Legacy.DB", Data()), ("readme.txt", Data()), ("cache.db", Data("not a database".utf8)), ("Index.sqlite3-wal", Data())
        ]
        for (name, contents) in others {
            try #require(FileManager.default.createFile(atPath: folder.appending(path: name).path(percentEncoded: false), contents: contents))
        }
        let sut = StoreDiscovery(locations: FakeStoreLocations(applicationSupport: folder), additionalDirectories: [])
        let expected = ["Legacy.DB", "Orders.sqlite", "default.store"]

        let actual = sut.stores().map(\.name)

        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "Orders.sqlite-wal").path(percentEncoded: false)))
        #expect(actual == expected)
    }

    @Test("The header says whether a store is in WAL mode; an empty file's mode isn't known yet, and sizes are read")
    func journalModeAndSize() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for (name, mode) in [("a-wal.sqlite", "WAL"), ("b-rollback.sqlite", "DELETE")] {
            var writer: OpaquePointer?
            try #require(sqlite3_open(folder.appending(path: name).path(percentEncoded: false), &writer) == SQLITE_OK)
            try #require(sqlite3_exec(writer, "PRAGMA journal_mode = \(mode); CREATE TABLE t(x);", nil, nil, nil) == SQLITE_OK)
            sqlite3_close(writer)
        }
        try #require(FileManager.default.createFile(atPath: folder.appending(path: "c-empty.db").path(percentEncoded: false), contents: Data()))
        let sut = StoreDiscovery(locations: FakeStoreLocations(documents: folder), additionalDirectories: [])
        let expected: [JournalMode] = [.wal, .rollback, .unknown]

        let actual = sut.stores()

        #expect(actual.map(\.journalMode) == expected)
        #expect(actual[0].size > 0)
        #expect(actual[2].size == 0)
        let canWrite = actual.map(\.canWriteSharedMemory)
        #expect(canWrite == [true, true, true])
    }

    @Test("Added folders are searched after the app's, and a store under two roots is listed once, under the first")
    func additionalDirectories() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let caches = folder.appending(path: "Caches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for file in [folder.appending(path: "main.sqlite"), caches.appending(path: "images.db")] {
            try #require(FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: Data()))
        }
        let sut = StoreDiscovery(locations: FakeStoreLocations(applicationSupport: folder), additionalDirectories: [caches, folder])
        let expectedLocations: [StoreLocation] = [.applicationSupport, .applicationSupport]

        let actual = sut.stores()

        #expect(actual.map(\.name) == ["images.db", "main.sqlite"])
        #expect(actual.map(\.location) == expectedLocations)
    }

    @Test("No folders, missing folders and an app group without a container find nothing")
    func nothing() {
        let missing = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let locations = FakeStoreLocations(applicationSupport: missing, appGroupIdentifiers: ["group.com.example.none"])

        let actual = StoreDiscovery(locations: locations, additionalDirectories: [missing]).stores()

        #expect(actual.isEmpty)
        #expect(StoreDiscovery(locations: FakeStoreLocations(), additionalDirectories: []).roots.isEmpty)
    }

    @Test("App groups are searched in the order of their identifiers, each under its own name")
    func appGroupOrder() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appending(path: "A", directoryHint: .isDirectory)
        let second = folder.appending(path: "B", directoryHint: .isDirectory)
        let locations = FakeStoreLocations(
            appGroupIdentifiers: ["group.z", "group.a"],
            appGroupContainers: ["group.z": second, "group.a": first]
        )
        let expected = [
            StoreDiscovery.SearchRoot(url: first, location: .appGroup("group.a")),
            StoreDiscovery.SearchRoot(url: second, location: .appGroup("group.z"))
        ]

        let actual = StoreDiscovery(locations: locations, additionalDirectories: []).roots

        #expect(actual == expected)
        #expect(StoreLocation.appGroup("group.a").title == "App group group.a")
    }
}
