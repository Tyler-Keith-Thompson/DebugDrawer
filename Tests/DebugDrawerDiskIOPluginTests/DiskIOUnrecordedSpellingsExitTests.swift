// Exit tests start a child process, which only the Mac's test runs can do. Installing swizzles
// Foundation for the whole process, so it is done only in a child.
#if os(macOS) && DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import Foundation
    import Testing

    // Pins what the README and the plugin's documentation say isn't captured: should an OS route
    // one of these through a swizzled method, this fails, and the documentation changes with it.
    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOUnrecordedSpellingsExitTests {
        @Test("Swift's FileHandle.write(contentsOf:), Data.write(to:) and Data(contentsOf:) reach no swizzled method")
        func swiftSpellingsUnrecorded() async {
            await #expect(processExitsWith: .success) {
                // The marker is written after the others, on the same thread, so once it is listed
                // anything recorded before it has been delivered too.
                @MainActor
                func callThenWaitForMarker() async throws {
                    let sut = DiskIOStore.shared
                    sut.install()
                    let directory = FileManager.default.temporaryDirectory.appending(path: "DiskIOUnrecorded-\(UUID().uuidString)")
                    try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        _ = FileManager.default.createFile(atPath: directory.appending(path: "handle").path(percentEncoded: false), contents: nil)
                        _ = FileManager.default.createFile(atPath: directory.appending(path: "marker").path(percentEncoded: false), contents: nil)
                    }

                    let handle = try FileHandle(forWritingTo: directory.appending(path: "handle"))
                    try handle.write(contentsOf: Data("swift".utf8))
                    try Data("data".utf8).write(to: directory.appending(path: "data"))
                    _ = try Data(contentsOf: directory.appending(path: "data"))
                    let marker = try FileHandle(forWritingTo: directory.appending(path: "marker"))
                    marker.write(Data("marker".utf8))
                    var subscription: AnyCancellable?
                    let events = await withCheckedContinuation { continuation in
                        subscription = sut.$events
                            .first { events in events.contains { $0.path.hasSuffix("/marker") } }
                            .sink { continuation.resume(returning: $0) }
                    }
                    subscription?.cancel()

                    let actual = events.filter { $0.path.contains(directory.lastPathComponent) }.map { ($0.path as NSString).lastPathComponent }
                    #expect(actual == ["marker"])
                }
                try await callThenWaitForMarker()
            }
        }
    }
#endif
