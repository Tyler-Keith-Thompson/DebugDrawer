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
    struct DiskIOInterposedWriteExitTests {
        @Test("With interposing installed, Data.write(to:) on the main thread is recorded as a main-thread write of its bytes")
        func dataWrite() async {
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
                    sut.unsafeInstallWithInterposing()
                    let name = "DiskIOInterposedDataWrite-\(UUID().uuidString)"
                    let file = FileManager.default.temporaryDirectory.appending(path: name)

                    try Data(repeating: 0x41, count: 1234).write(to: file)
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
                    #expect(events.map(\.error) == [nil])
                }
                try await writeThenWait()
            }
        }

        @Test("With interposing installed, Swift's FileHandle.write(contentsOf:) on the main thread is recorded as a main-thread write of its bytes")
        func fileHandleWrite() async {
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
                    sut.unsafeInstallWithInterposing()
                    let name = "DiskIOInterposedHandleWrite-\(UUID().uuidString)"
                    let file = FileManager.default.temporaryDirectory.appending(path: name)
                    // Made as the drawer's own work, so the write is the only call on the file.
                    DebugDrawerActivity.$isDrawerWork.withValue(true) {
                        _ = FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
                    }
                    let handle = try FileHandle(forWritingTo: file)

                    try handle.write(contentsOf: Data(repeating: 0x42, count: 567))
                    var subscription: AnyCancellable?
                    let events = await withCheckedContinuation { continuation in
                        subscription = sut.$events
                            .map { events in events.filter { ($0.path as NSString).lastPathComponent == name } }
                            .first { !$0.isEmpty }
                            .sink { continuation.resume(returning: $0) }
                    }
                    subscription?.cancel()

                    let expectedSize: Int64 = 567
                    #expect(events.map(\.operation) == [.write])
                    #expect(events.map(\.size) == [expectedSize])
                    #expect(events.map(\.isMainThread) == [true])
                }
                try await writeThenWait()
            }
        }

        @Test("With interposing installed, a write a swizzled method records is recorded once, not again by the interposer")
        func swizzledWriteOnce() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                // Both records, were there two, happen before the main queue turns, so the first
                // batch that lists the file holds them both.
                @MainActor
                func writeThenWait() async throws {
                    let sut = DiskIOStore.shared
                    sut.unsafeInstallWithInterposing()
                    let name = "DiskIOInterposedSwizzledWrite-\(UUID().uuidString)"
                    let file = FileManager.default.temporaryDirectory.appending(path: name)
                    DebugDrawerActivity.$isDrawerWork.withValue(true) {
                        _ = FileManager.default.createFile(atPath: file.path(percentEncoded: false), contents: nil)
                    }
                    let handle = try FileHandle(forWritingTo: file)

                    handle.write(Data(repeating: 0x44, count: 89))
                    var subscription: AnyCancellable?
                    let events = await withCheckedContinuation { continuation in
                        subscription = sut.$events
                            .map { events in events.filter { ($0.path as NSString).lastPathComponent == name } }
                            .first { !$0.isEmpty }
                            .sink { continuation.resume(returning: $0) }
                    }
                    subscription?.cancel()

                    let expectedSize: Int64 = 89
                    #expect(events.map(\.operation) == [.write])
                    #expect(events.map(\.size) == [expectedSize])
                }
                try await writeThenWait()
            }
        }
    }
#endif
