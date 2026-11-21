// Installing registers the plugin with the drawer of the process that runs it, and the reported
// token is kept for the process, so these run in a child process each, in a file of their own, as
// exit tests need one. The README's example is here, verbatim, rather than in DebugDrawerTests,
// which links core alone.
#if os(macOS) && DEBUG
    import DebugDrawer
    @testable import DebugDrawerNotificationsPlugin
    import Foundation
    import Testing

    @Suite("Notifications install, in a child process")
    struct NotificationsInstallExitTests {
        @Test("Install registers the plugin, reads the center, and reads it again on a change")
        func install() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    let center = FakeNotificationCenter(authorization: .denied)
                    let changes = FakeNotificationChangeSource()
                    let model = PushNotificationsInstallation.install(client: center, changes: changes)
                    let isRegistered = DebugDrawer.shared.globalPlugins.contains { $0.title == "Notifications" }
                    return (model, center, changes, isRegistered)
                }
                let (model, center, changes, isRegistered) = isExpected
                await model.refresh()
                let first = await model.center
                await MainActor.run { center.authorization = .authorized }
                await changes.change()
                let second = await model.center
                guard case let .loaded(before) = first, case let .loaded(after) = second else { exit(EXIT_FAILURE) }
                let isCorrect = isRegistered && before.settings.authorization == .denied && after.settings.authorization == .authorized
                exit(isCorrect ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("A token reported before install shows once installed; one reported after shows at once; so does a failure")
        func registration() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                struct RegistrationFailed: LocalizedError {
                    var errorDescription: String? {
                        "no valid aps-environment entitlement"
                    }
                }
                let isExpected = await MainActor.run {
                    PushNotifications.didRegisterForRemoteNotifications(withDeviceToken: Data([0x01]))
                    let model = PushNotificationsInstallation.install(
                        client: FakeNotificationCenter(authorization: .authorized), changes: FakeNotificationChangeSource()
                    )
                    let early = model.registration
                    PushNotifications.didRegisterForRemoteNotifications(withDeviceToken: Data([0x02]))
                    let late = model.registration
                    PushNotifications.didFailToRegisterForRemoteNotifications(withError: RegistrationFailed())
                    let failed = model.registration
                    return early == .registered(deviceToken: Data([0x01])) && late == .registered(deviceToken: Data([0x02]))
                        && failed == .failed(message: "no valid aps-environment entitlement")
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("Installing again registers the plugin once, keeping the token already reported")
        func installAgain() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let isExpected = await MainActor.run {
                    PushNotificationsInstallation.install(
                        client: FakeNotificationCenter(authorization: .authorized), changes: FakeNotificationChangeSource()
                    )
                    PushNotifications.didRegisterForRemoteNotifications(withDeviceToken: Data([0xAB]))
                    let model = PushNotificationsInstallation.install(
                        client: FakeNotificationCenter(authorization: .authorized), changes: FakeNotificationChangeSource()
                    )
                    let registered = DebugDrawer.shared.globalPlugins.filter { $0.title == "Notifications" }.count
                    return registered == 1 && model.registration == .registered(deviceToken: Data([0xAB]))
                }
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }

        @Test("README: Notifications")
        func readme() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                struct RegistrationFailed: Error {}
                await MainActor.run {
                    let deviceToken = Data([0xAB, 0xCD])
                    let error = RegistrationFailed()

                    // At startup:
                    PushNotifications.install()

                    // In application(_:didRegisterForRemoteNotificationsWithDeviceToken:):
                    PushNotifications.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)

                    // In application(_:didFailToRegisterForRemoteNotificationsWithError:):
                    PushNotifications.didFailToRegisterForRemoteNotifications(withError: error)

                    let isInstalled = DebugDrawer.shared.globalPlugins.contains { $0.title == "Notifications" }
                    // Exits while still on the main actor, before the first read install started
                    // can run: User Notifications, which it asks, needs an app bundle, and a test
                    // runner has none.
                    exit(isInstalled ? EXIT_SUCCESS : EXIT_FAILURE)
                }
            }
        }
    }
#endif
