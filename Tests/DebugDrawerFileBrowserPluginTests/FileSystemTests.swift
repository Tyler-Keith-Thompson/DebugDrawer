#if DEBUG
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import Testing

    // The real file system the browser uses, in a folder of its own under the temporary folder
    // (the test runner's, never the home folder or an app container); the model's tests use a
    // fake of it.
    @Suite(.timeLimit(.minutes(1)))
    struct FileSystemTests {
        @Test("A folder lists what is directly in it, each with its size, dates and whether it is a folder")
        func listing() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder.appending(path: "Sub/Deeper"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            try Data(count: 3).write(to: folder.appending(path: "alpha.txt"))
            try Data(count: 9).write(to: folder.appending(path: "Sub/inside.bin"))
            let sut = _FileSystem()
            let expected = ["Sub": true, "alpha.txt": false]

            let actual = try await sut.contents(of: folder)

            #expect(Dictionary(uniqueKeysWithValues: actual.map { ($0.name, $0.isDirectory) }) == expected)
            #expect(actual.first { $0.name == "alpha.txt" }?.size == 3)
            #expect(actual.first { $0.name == "Sub" }?.size == 0)
            #expect(actual.allSatisfy { $0.modified != nil && $0.created != nil })
        }

        @Test("A folder's total counts every file in it at any depth")
        func totalSize() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder.appending(path: "a/b/c"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            try Data(count: 10).write(to: folder.appending(path: "top.bin"))
            try Data(count: 50).write(to: folder.appending(path: "a/b/c/deep.bin"))
            let expected: Int64 = 60

            let actual = try await _FileSystem().totalSize(of: folder)

            #expect(actual == expected)
        }

        @Test("A read stops at its limit, and returns a shorter file whole")
        func read() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let file = folder.appending(path: "text.txt")
            try Data("hello world".utf8).write(to: file)
            let sut = _FileSystem()

            let start = try await sut.read(file, upTo: 5)
            let whole = try await sut.read(file, upTo: 1_000)

            #expect(start == Data("hello".utf8))
            #expect(whole == Data("hello world".utf8))
        }

        @Test("Copy and move refuse a destination that exists; remove deletes a folder with what it holds")
        func changes() async throws {
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder.appending(path: "Sub"), withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: folder) }
            let original = folder.appending(path: "a.txt")
            try Data("a".utf8).write(to: original)
            try Data("s".utf8).write(to: folder.appending(path: "Sub/s.txt"))
            let sut = _FileSystem()

            try await sut.copy(original, to: folder.appending(path: "b.txt"))
            try await sut.move(folder.appending(path: "b.txt"), to: folder.appending(path: "c.txt"))
            await #expect(throws: (any Error).self) { try await sut.copy(original, to: folder.appending(path: "c.txt")) }
            await #expect(throws: (any Error).self) { try await sut.move(original, to: folder.appending(path: "c.txt")) }
            try await sut.remove(folder.appending(path: "Sub"))

            let names = try FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).sorted()
            #expect(names == ["a.txt", "c.txt"])
            #expect(try Data(contentsOf: folder.appending(path: "c.txt")) == Data("a".utf8))
        }

        @Test("A folder that doesn't exist can't be listed or described")
        func missingFolder() async {
            let missing = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
            let sut = _FileSystem()

            await #expect(throws: (any Error).self) { try await sut.contents(of: missing) }
            await #expect(throws: (any Error).self) { try await sut.item(at: missing) }
        }
    }
#endif
