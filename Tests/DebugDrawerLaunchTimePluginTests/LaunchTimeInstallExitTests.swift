// installLaunchTime() adds its run-loop observer to the process's main run loop and registers with
// the process's drawer, so these run in a child process each, in a file of their own, as exit
// tests need one.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerLaunchTimePlugin
    import Foundation
    import Testing

    @Suite("Launch Time install, in a child process")
    struct LaunchTimeInstallExitTests {
        @Test("Unregistering removes the first-frame observer from the main run loop, twice harmlessly; installing again adds one")
        func uninstallRemovesTheObserver() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    guard let firstFrame = LaunchTimeModel.shared.firstFrameObserver as? _FirstFrameObserver else { return false }
                    DebugDrawer.shared.installLaunchTime()
                    guard let installed = firstFrame.runLoopObserver else { return false }
                    let isInstalled = CFRunLoopObserverIsValid(installed)
                        && CFRunLoopContainsObserver(CFRunLoopGetMain(), installed, .commonModes)
                    DebugDrawer.shared.unregisterGlobal(id: "LaunchTimePlugin")
                    DebugDrawer.shared.unregisterGlobal(id: "LaunchTimePlugin")
                    let isUninstalled = firstFrame.runLoopObserver == nil && !CFRunLoopObserverIsValid(installed)
                        && !CFRunLoopContainsObserver(CFRunLoopGetMain(), installed, .commonModes)
                        && !DebugDrawer.shared.globalPlugins.contains { $0.id == "LaunchTimePlugin" }
                    DebugDrawer.shared.installLaunchTime()
                    let isReinstalled = firstFrame.runLoopObserver.map(CFRunLoopObserverIsValid) == true
                    return isInstalled && isUninstalled && isReinstalled
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installed again, the plugin records the first frame when the main run loop goes idle")
        func reinstalledRecordsTheFirstFrame() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func firstFrame() async -> TimeInterval? {
                    DebugDrawer.shared.installLaunchTime()
                    DebugDrawer.shared.unregisterGlobal(id: "LaunchTimePlugin")
                    DebugDrawer.shared.installLaunchTime()
                    for await uptime in LaunchTimeModel.shared.$firstFrameUptime.values where uptime != nil {
                        return uptime
                    }
                    return nil
                }
                exit(await firstFrame() != nil ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
