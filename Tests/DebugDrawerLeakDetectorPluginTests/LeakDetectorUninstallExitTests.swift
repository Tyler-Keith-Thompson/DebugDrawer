// Uninstalling puts NSViewController's viewDidDisappear back and removes an observer from the main
// run loop of the process that runs it, so these run in a child process each, in a file of their
// own, as exit tests need one.
#if os(macOS) && DEBUG
    import AppKit
    @testable import DebugDrawer
    @testable import DebugDrawerLeakDetectorPlugin
    import ObjectiveC
    import Testing

    /// An object that opts in to lifetime tracking: one should be alive at a time.
    final class UninstallTrackedModel {
        init() {
            LeakDetector.trackLifetime(of: self)
        }
    }

    @Suite("Leak Detector uninstall, in a child process")
    struct LeakDetectorUninstallExitTests {
        @Test("Unregistering puts viewDidDisappear's implementation back; unregistering again changes nothing; installing again exchanges it again")
        func restoresViewDidDisappear() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor func isRestored() -> Bool {
                    let selector = #selector(NSViewController.viewDidDisappear)
                    let expected = class_getMethodImplementation(NSViewController.self, selector)

                    LeakDetector.install()
                    let installed = class_getMethodImplementation(NSViewController.self, selector)
                    DebugDrawer.shared.unregisterGlobal(id: LeakDetectorPlugin.pluginID)
                    let uninstalled = class_getMethodImplementation(NSViewController.self, selector)
                    let isListed = DebugDrawer.shared.globalPlugins.contains { $0.id == LeakDetectorPlugin.pluginID }
                    DebugDrawer.shared.unregisterGlobal(id: LeakDetectorPlugin.pluginID)
                    let twice = class_getMethodImplementation(NSViewController.self, selector)
                    LeakDetector.install()
                    let reinstalled = class_getMethodImplementation(NSViewController.self, selector)

                    return installed != expected && uninstalled == expected && !isListed && twice == expected && reinstalled == installed
                }
                exit(await MainActor.run { isRestored() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Unregistering drops the suspects, badge and monitor; objects tracked then aren't counted")
        func dropsSuspects() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor func isExpected() -> Bool {
                    LeakDetector.install()
                    let installedModels = [UninstallTrackedModel(), UninstallTrackedModel()]
                    let suspectsInstalled = LeakDetectorInstallation.store.visibleSuspects.count
                    let badgeInstalled = DebugDrawer.shared.badges[LeakDetectorPlugin.pluginID]

                    DebugDrawer.shared.unregisterGlobal(id: LeakDetectorPlugin.pluginID)
                    let suspectsUninstalled = LeakDetectorInstallation.store.suspects.count
                    let badgeUninstalled = DebugDrawer.shared.badges[LeakDetectorPlugin.pluginID]
                    let monitorUninstalled = LeakDetectorInstallation.monitor
                    let uninstalledModels = [UninstallTrackedModel(), UninstallTrackedModel()]
                    let suspectsTrackedUninstalled = LeakDetectorInstallation.store.suspects.count
                    let monitorAfterTracking = LeakDetectorInstallation.monitor

                    LeakDetector.install()
                    let reinstalledModels = [UninstallTrackedModel(), UninstallTrackedModel()]
                    let actual = LeakDetectorInstallation.store.visibleSuspects.map(\.count)

                    withExtendedLifetime([installedModels, uninstalledModels, reinstalledModels]) {}
                    return suspectsInstalled == 1 && badgeInstalled == 1
                        && suspectsUninstalled == 0 && badgeUninstalled == nil && monitorUninstalled == nil
                        && suspectsTrackedUninstalled == 0 && monitorAfterTracking == nil
                        && actual == [2]
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Stopping the main run loop's turn source removes its observer from the run loop")
        func turnSourceStops() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor func isRemoved() -> Bool {
                    guard let runLoop = CFRunLoopGetMain() else { return false }
                    let sut = MainRunLoopTurnSource()
                    sut.observe {}
                    guard let observer = sut.observer else { return false }
                    let observedWhileRunning = CFRunLoopContainsObserver(runLoop, observer, .commonModes)

                    sut.stop()
                    sut.stop()

                    return observedWhileRunning && !CFRunLoopContainsObserver(runLoop, observer, .commonModes)
                        && !CFRunLoopObserverIsValid(observer) && sut.observer == nil
                }
                exit(await MainActor.run { isRemoved() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("A plugin in two drawers keeps viewDidDisappear exchanged until the last removes it")
        func twoDrawers() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor func isExpected() -> Bool {
                    let suite = "LeakDetectorUninstallExitTests.\(UUID().uuidString)"
                    guard let first = UserDefaults(suiteName: suite + ".first"), let second = UserDefaults(suiteName: suite + ".second") else {
                        return false
                    }
                    let firstDrawer = DebugDrawer(defaults: first)
                    let secondDrawer = DebugDrawer(defaults: second)
                    let selector = #selector(NSViewController.viewDidDisappear)
                    let expected = class_getMethodImplementation(NSViewController.self, selector)
                    let sut = LeakDetectorPlugin(store: LeakDetectorInstallation.store)

                    firstDrawer.registerGlobal(sut)
                    secondDrawer.registerGlobal(sut)
                    firstDrawer.unregisterGlobal(id: sut.id)
                    let inSecond = class_getMethodImplementation(NSViewController.self, selector)
                    let monitorInSecond = LeakDetectorInstallation.monitor
                    secondDrawer.unregisterGlobal(id: sut.id)

                    return inSecond != expected && monitorInSecond != nil
                        && class_getMethodImplementation(NSViewController.self, selector) == expected
                        && LeakDetectorInstallation.monitor == nil
                        && !secondDrawer.globalPlugins.contains { $0.id == sut.id }
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Under a replacement made since, viewDidDisappear keeps it, and the plugin's under it calls straight through")
        func keptUnderAnotherReplacement() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor func isExpected() -> Bool {
                    final class Screen: NSViewController {
                        override func loadView() {
                            view = NSView(frame: .zero)
                        }
                    }
                    typealias ViewDidDisappear = @convention(c) (NSViewController, Selector) -> Void
                    let selector = #selector(NSViewController.viewDidDisappear)
                    guard let method = class_getInstanceMethod(NSViewController.self, selector) else { return false }

                    LeakDetector.install()
                    let plugins = unsafeBitCast(method_getImplementation(method), to: ViewDidDisappear.self)
                    nonisolated(unsafe) var otherCalls = 0
                    let other: @convention(block) (NSViewController) -> Void = { viewController in
                        otherCalls += 1
                        plugins(viewController, selector)
                    }
                    let otherIMP = imp_implementationWithBlock(other)
                    method_setImplementation(method, otherIMP)
                    DebugDrawer.shared.unregisterGlobal(id: LeakDetectorPlugin.pluginID)
                    let kept = method_getImplementation(method)
                    Screen().viewDidDisappear()

                    return kept == otherIMP && otherCalls == 1 && LeakDetectorInstallation.monitor == nil
                        && LeakDetectorInstallation.store.suspects.isEmpty
                }
                exit(await MainActor.run { isExpected() } ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
