// Exit tests start a child process, which only the Mac's test runs can do. Installing swizzles
// Foundation for the whole process, so it is done only in a child.
#if os(macOS) && DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOFailureExitTests {
        @Test("A call that fails is recorded with its error, and counted as a failure")
        func failedCallRecorded() async {
            await #expect(processExitsWith: .success) {
                @MainActor
                func failThenWait() async {
                    let sut = DiskIOStore.shared
                    sut.install()
                    let name = "DiskIOMissing-\(UUID().uuidString)"
                    let missing = FileManager.default.temporaryDirectory.appending(path: name)

                    let thrown = (try? FileManager.default.removeItem(at: missing)) == nil
                    var subscription: AnyCancellable?
                    let events = await withCheckedContinuation { continuation in
                        subscription = sut.$events
                            .map { events in events.filter { ($0.path as NSString).lastPathComponent == name } }
                            .first { !$0.isEmpty }
                            .sink { continuation.resume(returning: $0) }
                    }
                    subscription?.cancel()

                    #expect(thrown)
                    #expect(events.map(\.operation) == [.delete])
                    #expect(events.map { $0.error?.domain } == [NSCocoaErrorDomain])
                    #expect(events.map { $0.error?.code } == [CocoaError.fileNoSuchFile.rawValue])
                    #expect(sut.totals.failures == 1)
                }
                await failThenWait()
            }
        }
    }
#endif
