// Exit tests start a child process, which only the Mac's test runs can do. Installing swizzles
// Foundation for the whole process, so it is done only in a child.
#if os(macOS) && DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import Foundation
    import Testing

    // Pins what the README and the plugin's documentation say `installDiskIO()` doesn't capture:
    // should an OS route one of these through a swizzled method, this fails, and the documentation
    // changes with it. Under Bazel the test executable links DebugDrawerDiskIOInterposer, so this
    // also pins that its hooks record nothing until `unsafeInstallWithInterposing()` starts them.
    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOUnrecordedSpellingsExitTests {
        @Test("Without the interposing install, Swift's FileHandle.write(contentsOf:), Data.write(to:) and Data(contentsOf:) aren't recorded")
        func swiftSpellingsUnrecorded() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
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
