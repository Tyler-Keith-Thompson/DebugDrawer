// Exit tests start a child process, which only the Mac's test runs can do. Installing swizzles
// Foundation for the whole process, so it is done only in a child.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerDiskIOPlugin
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @Suite(.timeLimit(.minutes(1)))
    struct DiskIOPauseExitTests {
        @Test("A pause sent to the shared model drops the calls made meanwhile, resuming records again, and removing the plugin resumes")
        func pauseDropsCalls() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func waitUntilRecorded(_ path: String) async {
                    for await events in DiskIOStore.shared.$events.values where events.contains(where: { $0.path == path }) {
                        break
                    }
                }

                @MainActor
                func pauseThenResume() async throws {
                    let suite = temporarySuiteName("DiskIOPauseExitTests")
                    let defaults = try #require(UserDefaults(suiteName: suite))
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let drawer = DebugDrawer(defaults: defaults)
                    let directory = FileManager.default.temporaryDirectory.appending(path: "DiskIOPause-\(UUID().uuidString)")
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    defer { try? FileManager.default.removeItem(at: directory) }
                    let paused = directory.appending(path: "paused").path
                    let resumed = directory.appending(path: "resumed").path
                    let reinstalled = directory.appending(path: "reinstalled").path
                    let sut = DiskIOModel.shared
                    drawer.installDiskIO()

                    sut.perform(DiskIOCommand(.setPaused(true)))
                    let wrotePaused = FileManager.default.createFile(atPath: paused, contents: Data("1".utf8))
                    let snapshotWhilePaused = sut.snapshot
                    sut.perform(DiskIOCommand(.setPaused(false)))
                    _ = FileManager.default.createFile(atPath: resumed, contents: Data("2".utf8))
                    await waitUntilRecorded(resumed)
                    let recorded = sut.snapshot.events.map(\.path)
                    sut.perform(DiskIOCommand(.setPaused(true)))
                    drawer.unregisterGlobal(id: DiskIOPlugin().id)
                    let pausedAfterUninstall = sut.snapshot.isPaused
                    drawer.installDiskIO()
                    _ = FileManager.default.createFile(atPath: reinstalled, contents: Data("3".utf8))
                    await waitUntilRecorded(reinstalled)

                    #expect(wrotePaused)
                    #expect(snapshotWhilePaused.isPaused)
                    #expect(recorded.contains(resumed))
                    #expect(!recorded.contains(paused))
                    #expect(!pausedAfterUninstall)
                    drawer.unregisterGlobal(id: DiskIOPlugin().id)
                }
                try await pauseThenResume()
            }
        }
    }
#endif
