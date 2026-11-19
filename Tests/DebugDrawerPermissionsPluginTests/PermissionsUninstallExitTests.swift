// The production change source observes the app becoming active through the process's default
// notification center and makes a Location manager, and install registers with the process's
// drawer, so these run in a child process each, in a file of their own, as exit tests need one.
// Nothing here asks for a permission: only statuses are read, which never prompts.
#if os(macOS) && DEBUG
    import AppKit
    @testable import DebugDrawer
    @testable import DebugDrawerPermissionsPlugin
    import Foundation
    import Testing

    @Suite("Permissions uninstall, in a child process")
    struct PermissionsUninstallExitTests {
        @Test("Uninstalling stops the system change source, twice harmlessly; installing again observes again")
        func uninstallStopsTheSystemSource() async {
            await #expect(processExitsWith: .success) {
                @MainActor
                final class Calls {
                    var onCall: (() -> Void)?
                }

                @MainActor
                func isExpected() async -> Bool {
                    let calls = Calls()
                    let sut = SystemPermissionChangeSource()
                    let drawer = DebugDrawer.shared
                    let model = PrivacyPermissionsInstallation.install(
                        infoDictionary: [:], authority: FakePermissionAuthority(statuses: [:]), changes: sut
                    )
                    let isObservingOnceInstalled = sut.isObserving

                    drawer.unregisterGlobal(id: PermissionsPlugin.pluginID)
                    let isStopped = !sut.isObserving && !model.isObserving
                    PermissionsPlugin(model: model).uninstall(from: drawer)

                    drawer.registerGlobal(PermissionsPlugin(model: model))
                    let isObservingAgain = sut.isObserving && model.isObserving
                    // Replaced by the test's own report, so a report after reinstalling can be
                    // awaited.
                    await withCheckedContinuation { continuation in
                        calls.onCall = { continuation.resume() }
                        sut.observe { calls.onCall?() }
                        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
                    }
                    calls.onCall = nil
                    return isObservingOnceInstalled && isStopped && isObservingAgain
                }
                exit(await isExpected() ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("The Location reader lets go of its manager on stop, and makes a new one on the next read")
        func locationReaderLetsGo() async {
            await #expect(processExitsWith: .success) {
                @MainActor
                func isExpected() async -> Bool {
                    let sut = LocationPermissionReader()
                    let location = DeclaredPermission(kind: .location, usageDescriptions: [])
                    _ = await sut.status(of: location)
                    let isHoldingAfterRead = sut.isHoldingManager

                    sut.stop()
                    let isHoldingAfterStop = sut.isHoldingManager
                    sut.stop()
                    _ = await sut.status(of: location)

                    return isHoldingAfterRead && !isHoldingAfterStop && sut.isHoldingManager
                }
                exit(await isExpected() ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again replaces the plugin, and the old one's uninstall leaves the new model observing")
        func installAgainKeepsTheNewObserving() async {
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    let oldChanges = FakePermissionChangeSource()
                    let newChanges = FakePermissionChangeSource()
                    PrivacyPermissionsInstallation.install(
                        infoDictionary: [:], authority: FakePermissionAuthority(statuses: [:]), changes: oldChanges
                    )
                    let model = PrivacyPermissionsInstallation.install(
                        infoDictionary: [:], authority: FakePermissionAuthority(statuses: [:]), changes: newChanges
                    )
                    return !oldChanges.isObserving && newChanges.isObserving && model.isObserving
                        && DebugDrawer.shared.globalPlugins.count { $0.id == PermissionsPlugin.pluginID } == 1
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
