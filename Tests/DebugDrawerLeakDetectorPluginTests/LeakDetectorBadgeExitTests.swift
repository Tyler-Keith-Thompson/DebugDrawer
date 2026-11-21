// Installing the plugin on any drawer exchanges NSViewController's viewDidDisappear and observes
// the main run loop of the process that runs it, and the shared drawer is that process's, so these
// run in a child process each, in a file of their own, as exit tests need one.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerLeakDetectorPlugin
    import Foundation
    import Testing

    /// An object that opts in to lifetime tracking: one should be alive at a time.
    final class BadgeTrackedModel {
        init() {
            LeakDetector.trackLifetime(of: self)
        }
    }

    @Suite("Leak Detector badges, in a child process", .timeLimit(.minutes(1)))
    struct LeakDetectorBadgeExitTests {
        @Test("Installed only in a drawer of its own, the plugin badges that drawer as its suspects change, and never the shared one")
        func badgesItsOwnDrawer() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor func isExpected() -> Bool {
                    let suite = "LeakDetectorBadgeExitTests.badgesItsOwnDrawer.\(UUID().uuidString)"
                    guard let defaults = UserDefaults(suiteName: suite) else { return false }
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let drawer = DebugDrawer(defaults: defaults)
                    let store = LeakDetectorInstallation.store
                    let sut = LeakDetectorPlugin(store: store)
                    // Tracked before install: a suspect, which no drawer shows yet.
                    let models = [BadgeTrackedModel(), BadgeTrackedModel()]
                    let beforeInstall = [drawer.badges[sut.id], DebugDrawer.shared.badges[sut.id]]

                    drawer.registerGlobal(sut)
                    let installed = drawer.badges[sut.id]
                    guard let suspect = store.visibleSuspects.first else { return false }
                    store.ignore(suspect)
                    let ignored = drawer.badges[sut.id]
                    store.stopIgnoring()
                    let shownAgain = drawer.badges[sut.id]
                    let sharedWhileInstalled = DebugDrawer.shared.badges[sut.id]
                    drawer.unregisterGlobal(id: sut.id)
                    let removed = drawer.badges[sut.id]
                    store.update([suspect])
                    withExtendedLifetime(models) {}

                    return beforeInstall == [nil, nil] && installed == 1 && ignored == nil && shownAgain == 1
                        && sharedWhileInstalled == nil && removed == nil
                        && drawer.badges[sut.id] == nil && DebugDrawer.shared.badges[sut.id] == nil
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
