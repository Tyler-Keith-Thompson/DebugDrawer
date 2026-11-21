// Exit tests start a child process, which only the Mac's test runs can do. Installing swizzles
// Foundation for the whole process, so it is done only in a child.
#if os(macOS) && DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOBackgroundWriteExitTests {
        @Test("A FileHandle write off the main thread is recorded as not on the main thread")
        func backgroundWrite() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func writeThenWait() async throws {
                    let sut = DiskIOStore.shared
                    sut.install()
                    let name = "DiskIOBackgroundWrite-\(UUID().uuidString)"
                    let file = FileManager.default.temporaryDirectory.appending(path: name)
                    DebugDrawerActivity.$isDrawerWork.withValue(true) {
                        _ = FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
                    }
                    let handle = try FileHandle(forWritingTo: file)

                    let wroteOnMainThread = await Task.detached {
                        handle.write(Data(repeating: 0x42, count: 64))
                        return pthread_main_np() != 0
                    }.value
                    var subscription: AnyCancellable?
                    let events = await withCheckedContinuation { continuation in
                        subscription = sut.$events
                            .map { events in events.filter { ($0.path as NSString).lastPathComponent == name } }
                            .first { !$0.isEmpty }
                            .sink { continuation.resume(returning: $0) }
                    }
                    subscription?.cancel()

                    let expectedSize: Int64 = 64
                    #expect(!wroteOnMainThread)
                    #expect(events.map(\.operation) == [.write])
                    #expect(events.map(\.size) == [expectedSize])
                    #expect(events.map(\.isMainThread) == [false])
                }
                try await writeThenWait()
            }
        }
    }
#endif
