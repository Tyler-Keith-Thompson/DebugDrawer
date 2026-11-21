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
    struct DiskIOInterposedReadExitTests {
        @Test("With interposing installed, Data(contentsOf:) is recorded as a read of the file's bytes")
        func dataRead() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func readThenWait() async throws {
                    let sut = DiskIOStore.shared
                    sut.unsafeInstallWithInterposing()
                    let name = "DiskIOInterposedDataRead-\(UUID().uuidString)"
                    let file = FileManager.default.temporaryDirectory.appending(path: name)
                    // Written as the drawer's own work, so the read is the only call on the file.
                    try DebugDrawerActivity.$isDrawerWork.withValue(true) {
                        try Data(repeating: 0x43, count: 2048).write(to: file)
                    }

                    let contents = try Data(contentsOf: file)
                    var subscription: AnyCancellable?
                    let events = await withCheckedContinuation { continuation in
                        subscription = sut.$events
                            .map { events in events.filter { ($0.path as NSString).lastPathComponent == name } }
                            .first { !$0.isEmpty }
                            .sink { continuation.resume(returning: $0) }
                    }
                    subscription?.cancel()

                    let expectedSize: Int64 = 2048
                    #expect(contents.count == 2048)
                    #expect(events.map(\.operation) == [.read])
                    #expect(events.map(\.size) == [expectedSize])
                    #expect(events.map(\.isMainThread) == [true])
                }
                try await readThenWait()
            }
        }
    }
#endif
