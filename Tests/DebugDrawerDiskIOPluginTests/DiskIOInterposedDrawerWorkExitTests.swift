// Exit tests start a child process, which only the Mac's test runs can do. Installing swizzles and
// interposes for the whole process, so it is done only in a child. dyld interposes only for images
// loaded at launch, and SwiftPM loads the tests with dlopen, so these run under Bazel, whose test
// executable links DebugDrawerDiskIOInterposer at launch.
#if os(macOS) && DEBUG && !SWIFT_PACKAGE
    import Combine
    import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOInterposedDrawerWorkExitTests {
        @Test("With interposing installed, Swift file calls made as the drawer's own work aren't recorded, on the calling thread or in a task")
        func drawerWorkLeftOut() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                // The marker is written after the drawer's calls, on the same thread, so once it is
                // listed every call before it has been delivered too.
                @MainActor
                func callThenWaitForMarker() async throws {
                    let sut = DiskIOStore.shared
                    sut.unsafeInstallWithInterposing()
                    let directory = FileManager.default.temporaryDirectory.appending(path: "DiskIOInterposedDrawerWork-\(UUID().uuidString)")
                    let marker = "Marker-\(UUID().uuidString)"

                    try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                        try Data("a".utf8).write(to: directory.appending(path: "a"))
                        _ = try Data(contentsOf: directory.appending(path: "a"))
                        let handle = try FileHandle(forWritingTo: directory.appending(path: "a"))
                        try handle.write(contentsOf: Data("more".utf8))
                        try handle.close()
                    }
                    // A child task inherits the binding and runs off the main thread.
                    try await DebugDrawerActivity.$isDrawerWork.withValue(true) {
                        try await withThrowingTaskGroup(of: Void.self) { group in
                            group.addTask {
                                try Data("b".utf8).write(to: directory.appending(path: "b"))
                                _ = try Data(contentsOf: directory.appending(path: "b"))
                            }
                            try await group.waitForAll()
                        }
                    }
                    try Data("marker".utf8).write(to: directory.appending(path: marker))
                    var subscription: AnyCancellable?
                    let events = await withCheckedContinuation { continuation in
                        subscription = sut.$events
                            .first { events in events.contains { ($0.path as NSString).lastPathComponent == marker } }
                            .sink { continuation.resume(returning: $0) }
                    }
                    subscription?.cancel()

                    let actual = events.filter { $0.path.contains(directory.lastPathComponent) }.map { ($0.path as NSString).lastPathComponent }
                    #expect(actual == [marker])
                }
                try await callThenWaitForMarker()
            }
        }
    }
#endif
