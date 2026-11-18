// Exit tests start a child process, which only the Mac's test runs can do. Installing swizzles
// Foundation for the whole process, so it is done only in a child.
#if os(macOS) && DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOCreateExitTests {
        @Test("Creating a folder and a file records a create for each, once, with the file's bytes")
        func createsRecorded() async {
            await #expect(processExitsWith: .success) {
                // `createDirectory(at:)` creates through `createDirectory(atPath:)`; the folder is
                // still recorded once. The file is created after it, on the same thread, so once
                // the file is listed the folder has been delivered too.
                @MainActor
                func createThenWait() async throws {
                    let sut = DiskIOStore.shared
                    sut.install()
                    let folder = "DiskIOCreate-\(UUID().uuidString)"
                    let directory = FileManager.default.temporaryDirectory.appending(path: folder)

                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    let file = directory.appending(path: "file").path(percentEncoded: false)
                    _ = FileManager.default.createFile(atPath: file, contents: Data("hello".utf8))
                    var subscription: AnyCancellable?
                    let events = await withCheckedContinuation { continuation in
                        subscription = sut.$events
                            .map { events in events.filter { $0.path.contains(folder) } }
                            .first { events in events.contains { $0.path.hasSuffix("/file") } }
                            .sink { continuation.resume(returning: $0) }
                    }
                    subscription?.cancel()

                    // Newest first.
                    let actual = events.map { "\($0.operation.name) \(($0.path as NSString).lastPathComponent) \($0.size)" }
                    #expect(actual == ["Create file 5", "Create \(folder) 0"])
                    #expect(sut.totals.creates >= 2)
                }
                try await createThenWait()
            }
        }
    }
#endif
