// Installing registers the plugin with the drawer of the process that runs it, so these run in a
// child process each, in a file of their own, as exit tests need one. The README's example is
// here, verbatim, rather than in DebugDrawerTests, which links core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerPermissionsPlugin
    import Foundation
    import Testing

    @Suite("Permissions install, in a child process")
    struct PermissionsInstallExitTests {
        @Test("Install registers the plugin over the declared permissions, reads them, and reads them again on a change")
        func install() async {
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    let authority = FakePermissionAuthority(statuses: [.camera: .denied, .notifications: .authorized])
                    let changes = FakePermissionChangeSource()
                    let model = PrivacyPermissionsInstallation.install(
                        infoDictionary: ["NSCameraUsageDescription": "Scans receipts"], authority: authority, changes: changes
                    )
                    let isRegistered = DebugDrawer.shared.globalPlugins.contains { $0.title == "Permissions" }
                    return (model, authority, changes, isRegistered)
                }
                let (model, authority, changes, isRegistered) = isExpected
                await model.refresh()
                let first = await model.rows.map(\.status)
                await MainActor.run { authority.statuses[.camera] = .authorized }
                await changes.change()
                let second = await model.rows.map(\.status)
                let kinds = await model.rows.map(\.permission.kind)
                let isCorrect = isRegistered && kinds == [.camera, .notifications]
                    && first == [.denied, .authorized] && second == [.authorized, .authorized]
                exit(isCorrect ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again registers the plugin once, over the Info.plist read again")
        func installAgain() async {
            await #expect(processExitsWith: .success) {
                let isExpected = await MainActor.run {
                    PrivacyPermissionsInstallation.install(
                        infoDictionary: [:], authority: FakePermissionAuthority(statuses: [:]), changes: FakePermissionChangeSource()
                    )
                    let model = PrivacyPermissionsInstallation.install(
                        infoDictionary: ["NSContactsUsageDescription": "Finds friends"],
                        authority: FakePermissionAuthority(statuses: [:]), changes: FakePermissionChangeSource()
                    )
                    let registered = DebugDrawer.shared.globalPlugins.filter { $0.title == "Permissions" }.count
                    return registered == 1 && model.permissions.map(\.kind) == [.contacts, .notifications]
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: Permissions")
        func readme() async {
            await #expect(processExitsWith: .success) {
                await MainActor.run {
                    // At startup:
                    PrivacyPermissions.install()

                    let isInstalled = DebugDrawer.shared.globalPlugins.contains { $0.title == "Permissions" }
                    // Exits while still on the main actor, before the first read install started
                    // can run: User Notifications, which it asks, needs an app bundle, and a test
                    // runner has none.
                    exit(isInstalled ? EXIT_SUCCESS : EXIT_FAILURE)
                }
            }
        }
    }
#endif
