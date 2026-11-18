// Exit tests start a child process, which only the Mac's test runs can do. Installing swizzles
// Foundation for the whole process, so it is done only in a child.
#if os(macOS) && DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOMainThreadWriteExitTests {
        @Test("A FileHandle write on the main thread is recorded as a main-thread write of its bytes")
        func mainThreadWrite() async {
            await #expect(processExitsWith: .success) {
                @MainActor
                func writeThenWait() async throws {
                    let sut = DiskIOStore.shared
                    sut.install()
                    let name = "DiskIOMainThreadWrite-\(UUID().uuidString)"
                    let file = FileManager.default.temporaryDirectory.appending(path: name)
                    // Made as the drawer's own work, so the write is the only call on the file.
                    DebugDrawerActivity.$isDrawerWork.withValue(true) {
                        _ = FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
                    }
                    let handle = try FileHandle(forWritingTo: file)

                    handle.write(Data(repeating: 0x41, count: 1234))
                    var subscription: AnyCancellable?
                    let events = await withCheckedContinuation { continuation in
                        subscription = sut.$events
                            .map { events in events.filter { ($0.path as NSString).lastPathComponent == name } }
                            .first { !$0.isEmpty }
                            .sink { continuation.resume(returning: $0) }
                    }
                    subscription?.cancel()

                    let expectedSize: Int64 = 1234
                    #expect(events.map(\.operation) == [.write])
                    #expect(events.map(\.size) == [expectedSize])
                    #expect(events.map(\.isMainThread) == [true])
                    #expect(sut.totals.mainThreadCalls >= 1)
                }
                try await writeThenWait()
            }
        }
    }
#endif
