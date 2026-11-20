// What listing and deleting a large container costs. The plugin exists in debug builds only, so
// it is measured there; `--config=release` builds this target without it, and runs
// ReleaseInstallTests instead.
#if DEBUG
    @testable import DebugDrawerAppStateResetPlugin
    @testable import DebugDrawerAppStateReset
    import Foundation
    import Testing

    // The plugin lists a container's files each time it is shown and deletes them on Reset, both off
    // the main actor; a container of thousands of files has to take seconds at most, not minutes.
    @Suite(.timeLimit(.minutes(1)))
    struct ContainerWalkTests {
        @Test("Listing and deleting 4,000 files in 40 folders, one holding a kept item to descend into, takes under 10 seconds")
        func largeContainer() async throws {
            let root = FileManager.default.temporaryDirectory.appending(path: "AppStateReset-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: root) }
            let documents = root.appending(path: "Documents", directoryHint: .isDirectory)
            for folder in 0 ..< 40 {
                let directory = documents.appending(path: "Folder \(folder)", directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                for file in 0 ..< 100 {
                    try Data(repeating: UInt8(file), count: 64).write(to: directory.appending(path: "\(file).dat"))
                }
            }
            let kept = documents.appending(path: "Folder 0/DebugDrawer Notes")
            try Data("kept".utf8).write(to: kept)
            let sut = AppContainer(
                files: [FileArea(name: "Documents", directory: documents)], caches: [],
                kept: [kept], appFolderName: "com.example.app"
            )
            let clock = ContinuousClock()
            let start = clock.now

            let entries = await sut.entries(in: sut.files, includingDebugDrawer: true)
            let failures = await sut.delete(entries)
            let elapsed = clock.now - start

            #expect(entries.count == 39 + 100)
            #expect(entries.map(\.byteCount).reduce(0, +) == 4000 * 64)
            #expect(failures.isEmpty)
            #expect(FileManager.default.fileExists(atPath: kept.path(percentEncoded: false)))
            #expect(elapsed < .seconds(10))
        }
    }
#endif
