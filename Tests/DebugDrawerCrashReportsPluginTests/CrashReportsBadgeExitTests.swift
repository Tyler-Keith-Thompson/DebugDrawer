// Installing the plugin on any drawer installs the signal and uncaught-exception handlers of the
// process that runs it, and the shared drawer is that process's, so these run in a child process
// each, in a file of their own, as exit tests need one.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerCrashReportsPlugin
    import Foundation
    import Testing

    @Suite("Crash Reports badges, in a child process", .timeLimit(.minutes(1)))
    struct CrashReportsBadgeExitTests {
        @Test("Installed only in a drawer of its own, the plugin badges that drawer as its unseen reports change, and never the shared one")
        func badgesItsOwnDrawer() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let path = directory.path(percentEncoded: false)

            await #expect(processExitsWith: .success) { [home = home as String, path = path as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor func isExpected() -> Bool {
                    func report(_ title: String, at seconds: TimeInterval) -> CrashReport {
                        CrashReport(
                            id: UUID(), date: Date(timeIntervalSince1970: seconds), title: title, reason: nil, appVersion: nil,
                            frames: [], source: .captured, isSeen: false
                        )
                    }
                    let suite = "CrashReportsBadgeExitTests.badgesItsOwnDrawer.\(UUID().uuidString)"
                    guard let defaults = UserDefaults(suiteName: suite) else { return false }
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let drawer = DebugDrawer(defaults: defaults)
                    let store = CrashReportStore(directory: URL(filePath: path, directoryHint: .isDirectory))
                    let sut = CrashReportsPlugin(store: store)
                    store.add(report("SIGSEGV", at: 1))
                    let beforeInstall = [drawer.badges[sut.id], DebugDrawer.shared.badges[sut.id]]

                    drawer.registerGlobal(sut)
                    let installed = drawer.badges[sut.id]
                    store.add(report("SIGBUS", at: 2))
                    let added = drawer.badges[sut.id]
                    store.markAllSeen()
                    let seen = drawer.badges[sut.id]
                    store.add(report("SIGABRT", at: 3))
                    let sharedWhileInstalled = DebugDrawer.shared.badges[sut.id]
                    drawer.unregisterGlobal(id: sut.id)
                    let removed = drawer.badges[sut.id]
                    store.add(report("SIGILL", at: 4))

                    return beforeInstall == [nil, nil] && installed == 1 && added == 2 && seen == nil
                        && sharedWhileInstalled == nil && removed == nil
                        && drawer.badges[sut.id] == nil && DebugDrawer.shared.badges[sut.id] == nil
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installed through CrashReports.install(directory:), the plugin badges the shared drawer as its unseen reports change")
        func installBadgesTheSharedDrawer() async throws {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let crash = "DebugDrawer crash report 1\ntime 1763290000\nsignal 11\nframes\n0 Example 0x1\nend\n"
            try Data(crash.utf8).write(to: directory.appending(path: "crash.txt"))
            let path = directory.path(percentEncoded: false)

            await #expect(processExitsWith: .success) { [home = home as String, path = path as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor func isExpected() -> Bool {
                    CrashReports.install(directory: URL(filePath: path, directoryHint: .isDirectory))
                    let installed = DebugDrawer.shared.badges[CrashReportsPlugin.pluginID]
                    let plugin = DebugDrawer.shared.globalPlugins.first { $0.id == CrashReportsPlugin.pluginID }
                    guard let delete = plugin?.actions.first(where: { $0.title == "Delete crash reports" }) else { return false }

                    delete.perform()

                    return installed == 1 && DebugDrawer.shared.badges[CrashReportsPlugin.pluginID] == nil
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
