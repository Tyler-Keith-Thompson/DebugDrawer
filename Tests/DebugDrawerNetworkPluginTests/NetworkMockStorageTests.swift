#if DEBUG
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    // The production storage, on disk in a temporary directory of the test's own.
    @MainActor
    @Suite
    struct NetworkMockStorageTests {
        @Test("Nothing saved reads as nil; saved rules read back, and a model over the directory loads them")
        func rulesOnDisk() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = _NetworkMockStorage(directory: directory)
            let rule = NetworkMockRule(name: "Disk", matcher: .init(host: .exact("api.test")), response: .init(status: 202))
            let before = try sut.readRules()

            NetworkMocksModel(storage: sut, active: NetworkMockRules()).save(rule)
            let relaunch = NetworkMocksModel(storage: _NetworkMockStorage(directory: directory), active: NetworkMockRules())
            relaunch.load()

            #expect(before == nil)
            #expect(relaunch.rules == [rule])
            #expect(FileManager.default.fileExists(atPath: directory.appending(path: "rules.json").path(percentEncoded: false)))
        }

        @Test("A body is kept under its own name with its extension, read back, and removed")
        func bodiesOnDisk() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = _NetworkMockStorage(directory: directory)
            let data = Data(#"{"users":[]}"#.utf8)

            let name = try sut.addBody(data, fileExtension: "json")
            let read = sut.body(named: name)
            sut.removeBody(named: name)

            #expect(name.hasSuffix(".json"))
            #expect(read == data)
            #expect(sut.body(named: name) == nil)
        }

        @Test("Importing a file copies it into the storage, so the rule keeps it when the original goes")
        func importBody() throws {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let original = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
            try Data("[1,2,3]".utf8).write(to: original)
            let storage = _NetworkMockStorage(directory: directory)
            let sut = NetworkMocksModel(storage: storage, active: NetworkMockRules())

            let name = try #require(sut.importBody(from: original))
            try FileManager.default.removeItem(at: original)

            #expect(storage.body(named: name) == Data("[1,2,3]".utf8))
            #expect(name.hasSuffix(".json"))
        }

        @Test("Importing a file that isn't there says the file couldn't be read")
        func importMissing() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: directory) }
            let sut = NetworkMocksModel(storage: _NetworkMockStorage(directory: directory), active: NetworkMockRules())

            let actual = sut.importBody(from: directory.appending(path: "missing.json"))

            #expect(actual == nil)
            #expect(sut.issue == .fileUnreadable)
        }
    }
#endif
