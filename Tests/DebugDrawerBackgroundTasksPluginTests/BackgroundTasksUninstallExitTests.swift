// The production change source observes the app becoming active through the process's default
// notification center, and install registers with the process's drawer, so these run in a child
// process each, in a file of their own, as exit tests need one.
#if os(macOS) && DEBUG
    import AppKit
    @testable import DebugDrawer
    @testable import DebugDrawerBackgroundTasksPlugin
    import Foundation
    import Testing

    @Suite("Background Tasks uninstall, in a child process")
    struct BackgroundTasksUninstallExitTests {
        @Test("Uninstalling removes the app-activation observer, twice harmlessly; installing again adds one that reports")
        func uninstallRemovesTheObserver() async {
            await #expect(processExitsWith: .success) {
                @MainActor
                final class Calls {
                    var count = 0
                    var onCall: (() -> Void)?
                }

                @MainActor
                func isExpected() async -> Bool {
                    let calls = Calls()
                    let sut = AppActivationChangeSource()
                    let report: @MainActor () async -> Void = {
                        calls.count += 1
                        calls.onCall?()
                    }
                    func activate() async {
                        await withCheckedContinuation { continuation in
                            calls.onCall = { continuation.resume() }
                            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
                        }
                        calls.onCall = nil
                    }
                    let drawer = DebugDrawer.shared
                    let model = BackgroundTaskRequestsInstallation.install(infoDictionary: [:], client: FakeBackgroundTaskScheduler(), changes: sut)
                    // Replaced by the test's own count, so each report can be awaited.
                    sut.observe(report)
                    await activate()

                    drawer.unregisterGlobal(id: BackgroundTasksPlugin.pluginID)
                    let isStopped = !sut.isObserving && !model.isObserving
                    NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
                    BackgroundTasksPlugin(model: model).uninstall(from: drawer)

                    drawer.registerGlobal(BackgroundTasksPlugin(model: model))
                    let isObservingAgain = sut.isObserving && model.isObserving
                    sut.observe(report)
                    await activate()
                    // A leftover observer would have reported the second post and the third too,
                    // each queued ahead of the report awaited.
                    return isStopped && isObservingAgain && calls.count == 2
                }
                exit(await isExpected() ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again replaces the plugin, and the old one's uninstall leaves the new model observing")
        func installAgainKeepsTheNewObserving() async {
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    let oldChanges = FakeBackgroundTaskChangeSource()
                    let newChanges = FakeBackgroundTaskChangeSource()
                    BackgroundTaskRequestsInstallation.install(infoDictionary: [:], client: FakeBackgroundTaskScheduler(), changes: oldChanges)
                    let model = BackgroundTaskRequestsInstallation.install(
                        infoDictionary: [:], client: FakeBackgroundTaskScheduler(), changes: newChanges
                    )
                    return !oldChanges.isObserving && newChanges.isObserving && model.isObserving
                        && DebugDrawer.shared.globalPlugins.count { $0.id == BackgroundTasksPlugin.pluginID } == 1
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
