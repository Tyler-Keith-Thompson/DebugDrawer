// Installing the plugin on any drawer puts an observer on the main run loop and starts a watcher
// thread in the process that runs it, and the shared drawer is that process's, so these run in a
// child process each, in a file of their own, as exit tests need one.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerHangDetectorPlugin
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @Suite("Hang Detector badges, in a child process", .timeLimit(.minutes(1)))
    struct HangDetectorBadgeExitTests {
        @Test("Installed only in a drawer of its own, the plugin badges that drawer as its unseen hangs change, and never the shared one")
        func badgesItsOwnDrawer() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor func isExpected() -> Bool {
                    func hang(at seconds: TimeInterval) -> HangEvent {
                        HangEvent(
                            id: UUID(), date: Date(timeIntervalSince1970: seconds), duration: .milliseconds(300), frames: [],
                            source: .detected, isSeen: false
                        )
                    }
                    let suite = temporarySuiteName("HangDetectorBadgeExitTests.badgesItsOwnDrawer")
                    guard let defaults = UserDefaults(suiteName: suite) else { return false }
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let drawer = DebugDrawer(defaults: defaults)
                    let store = HangStore(threshold: .milliseconds(250))
                    let sut = HangDetectorPlugin(store: store)
                    store.add(hang(at: 1))
                    let beforeInstall = [drawer.badges[sut.id], DebugDrawer.shared.badges[sut.id]]

                    drawer.registerGlobal(sut)
                    let installed = drawer.badges[sut.id]
                    store.add(hang(at: 2))
                    let added = drawer.badges[sut.id]
                    store.markAllSeen()
                    let seen = drawer.badges[sut.id]
                    store.add(hang(at: 3))
                    let sharedWhileInstalled = DebugDrawer.shared.badges[sut.id]
                    drawer.unregisterGlobal(id: sut.id)
                    let removed = drawer.badges[sut.id]
                    store.add(hang(at: 4))

                    return beforeInstall == [nil, nil] && installed == 1 && added == 2 && seen == nil
                        && sharedWhileInstalled == nil && removed == nil
                        && drawer.badges[sut.id] == nil && DebugDrawer.shared.badges[sut.id] == nil
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installed through HangDetector.install(threshold:), the plugin badges the shared drawer as its unseen hangs change")
        func installBadgesTheSharedDrawer() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor func isExpected() -> Bool {
                    HangDetector.install()
                    guard let store = HangDetectorInstallation.installedStore else { return false }
                    let installed = DebugDrawer.shared.badges[HangDetectorPlugin.pluginID]

                    store.add(HangEvent(
                        id: UUID(), date: Date(timeIntervalSince1970: 1), duration: .milliseconds(300), frames: [],
                        source: .detected, isSeen: false
                    ))
                    let added = DebugDrawer.shared.badges[HangDetectorPlugin.pluginID]
                    store.markAllSeen()

                    return installed == nil && added == 1 && DebugDrawer.shared.badges[HangDetectorPlugin.pluginID] == nil
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
