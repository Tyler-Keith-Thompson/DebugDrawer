// Installing exchanges NSViewController's viewDidDisappear and observes the main run loop for the
// life of the process that does it, so these run in a child process each, in a file of their own,
// as exit tests need one. The README's examples are here, verbatim, rather than in
// DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import AppKit
    import Combine
    import DebugDrawer
    @testable import DebugDrawerLeakDetectorPlugin
    import ObjectiveC
    import Testing

    /// A screen that holds a closure that holds the screen: the retain cycle the detector is for.
    final class LeakingProfileViewController: NSViewController {
        private var onRefresh: (() -> Void)?
        private var refreshCount = 0

        override func loadView() {
            view = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            onRefresh = { self.refreshCount += 1 }
        }

        /// Drops the closure that holds the screen, so it can deallocate.
        func breakCycle() {
            onRefresh = nil
        }
    }

    /// The same screen with the closure capturing it weakly, which deallocates once removed.
    final class ReleasedProfileViewController: NSViewController {
        private var onRefresh: (() -> Void)?
        private var refreshCount = 0

        override func loadView() {
            view = NSView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
            onRefresh = { [weak self] in self?.refreshCount += 1 }
        }
    }

    /// The container the screens are shown in.
    final class ContainerViewController: NSViewController {
        override func loadView() {
            view = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 200))
        }
    }

    // The README's example: an object that opts in, with one call: one should be alive at a time.
    final class ProfileModel {
        init() {
            LeakDetector.trackLifetime(of: self)
        }
    }

    @Suite("Leak Detector install, in a child process")
    struct LeakDetectorInstallExitTests {
        @Test("Install registers Leaks and exchanges viewDidDisappear once; installing again exchanges nothing back")
        func install() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isInstalledOnce = await MainActor.run {
                    let selector = #selector(NSViewController.viewDidDisappear)
                    let original = class_getMethodImplementation(NSViewController.self, selector)
                    LeakDetector.install()
                    let first = class_getMethodImplementation(NSViewController.self, selector)
                    LeakDetector.install()
                    let second = class_getMethodImplementation(NSViewController.self, selector)
                    let registered = DebugDrawer.shared.globalPlugins.count { $0.title == "Leaks" }
                    return original != first && first == second && registered == 1
                }
                exit(isInstalledOnce ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("A view controller with a retain cycle, removed from its parent, is flagged at the end of the next run-loop turn; one without is not")
        func flagsRetainCycle() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor func isFlagged() async -> Bool {
                    LeakDetector.install()
                    // On screen, so AppKit sends the appearance callbacks; out of sight, borderless
                    // and never key, so it takes nothing from the Mac's screen.
                    let window = NSWindow(
                        contentRect: CGRect(x: -10000, y: -10000, width: 200, height: 200), styleMask: .borderless, backing: .buffered, defer: false
                    )
                    let container = ContainerViewController()
                    window.contentViewController = container
                    window.orderFrontRegardless()
                    weak var weakLeaking: LeakingProfileViewController?
                    weak var weakReleased: ReleasedProfileViewController?
                    var subscription: AnyCancellable?
                    // Awaiting frees the main thread to turn its run loop; the suspects change
                    // only at the end of a turn.
                    await withCheckedContinuation { flagged in
                        subscription = LeakDetectorInstallation.store.$suspects.dropFirst().first().sink { _ in flagged.resume() }
                        // An app's run loop drains an autorelease pool each turn; nothing does in
                        // a test process, so the test drains the one AppKit's calls autorelease
                        // into.
                        autoreleasepool {
                            let leaking = LeakingProfileViewController()
                            let released = ReleasedProfileViewController()
                            weakLeaking = leaking
                            weakReleased = released
                            for child in [leaking, released] as [NSViewController] {
                                container.addChild(child)
                                container.view.addSubview(child.view)
                            }

                            for child in [leaking, released] as [NSViewController] {
                                child.view.removeFromSuperview()
                                child.removeFromParent()
                            }
                        }
                    }
                    subscription?.cancel()

                    let names = LeakDetectorInstallation.store.visibleSuspects.map(\.type.name)
                    let badge = DebugDrawer.shared.badges[LeakDetectorPlugin.pluginID]
                    window.orderOut(nil)
                    return names == ["LeakingProfileViewController"] && badge == 1 && weakLeaking != nil && weakReleased == nil
                }
                exit(await isFlagged() ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("A flagged view controller stops being a suspect once its cycle is broken and it deallocates")
        func clearsWhenReleased() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor func isCleared() async -> Bool {
                    LeakDetector.install()
                    let window = NSWindow(
                        contentRect: CGRect(x: -10000, y: -10000, width: 200, height: 200), styleMask: .borderless, backing: .buffered, defer: false
                    )
                    let container = ContainerViewController()
                    window.contentViewController = container
                    window.orderFrontRegardless()
                    var subscription: AnyCancellable?
                    // Held only by its own cycle once removed; `unowned` lets the test break it.
                    unowned var screen: LeakingProfileViewController?
                    await withCheckedContinuation { flagged in
                        subscription = LeakDetectorInstallation.store.$suspects.dropFirst().first().sink { _ in flagged.resume() }
                        // The test drains the autorelease pool an app's run loop would.
                        autoreleasepool {
                            let leaking = LeakingProfileViewController()
                            screen = leaking
                            container.addChild(leaking)
                            container.view.addSubview(leaking.view)
                            leaking.view.removeFromSuperview()
                            leaking.removeFromParent()
                        }
                    }
                    let flaggedCount = LeakDetectorInstallation.store.visibleSuspects.count

                    await withCheckedContinuation { cleared in
                        subscription = LeakDetectorInstallation.store.$suspects.dropFirst().first().sink { _ in cleared.resume() }
                        autoreleasepool { screen?.breakCycle() }
                    }
                    subscription?.cancel()

                    window.orderOut(nil)
                    return flaggedCount == 1 && LeakDetectorInstallation.store.visibleSuspects.isEmpty
                        && DebugDrawer.shared.badges[LeakDetectorPlugin.pluginID] == nil
                }
                exit(await isCleared() ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: Leak Detector")
        func readme() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isFlagged = await MainActor.run {
                    // At startup: watches the app's view controllers.
                    LeakDetector.install()

                    let first = ProfileModel()
                    let second = ProfileModel()

                    let actual = LeakDetectorInstallation.store.visibleSuspects.map(\.summary)
                    withExtendedLifetime([first, second]) {}
                    return actual == ["2 alive, at most 1 expected"]
                }
                exit(isFlagged ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("An object tracked before install is shown once the plugin is installed")
        func trackedBeforeInstall() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isShown = await MainActor.run {
                    let models = [ProfileModel(), ProfileModel()]

                    LeakDetector.install()

                    let actual = LeakDetectorInstallation.store.visibleSuspects.map(\.count)
                    let badge = DebugDrawer.shared.badges[LeakDetectorPlugin.pluginID]
                    withExtendedLifetime(models) {}
                    return actual == [2] && badge == 1
                }
                exit(isShown ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
