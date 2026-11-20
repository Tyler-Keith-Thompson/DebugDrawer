// The README's production push registration example, verbatim, so the README cannot drift from the
// code. No session is opened: the default settings reader asks User Notifications' center, which a
// test runner, having no bundle identifier, doesn't have.
#if DEBUG
    import DebugDrawer
    import DebugDrawerNotifications
    import DebugDrawerReceiver
    import Foundation
    import Testing

    @MainActor
    final class ProductionPush {
        let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
        let receiver: DebugDrawerReceiver
        let pushRegistration: PushRegistrationMirror

        init(container: URL) throws {
            receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
            pushRegistration = PushRegistrationMirror(sessions: sessions)
            receiver.enable(.pushRegistration(pushRegistration))
            try receiver.start()
        }

        /// From application(_:didRegisterForRemoteNotificationsWithDeviceToken:).
        func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
            pushRegistration.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        }
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test(
            "Production builds: push token and environment: the capability is served, and empty until a session opens",
            .timeLimit(.minutes(1))
        )
        func productionPush() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "READMEPush-\(UUID().uuidString)")
            let push = try ProductionPush(container: container)
            defer { push.receiver.stop() }
            push.didRegisterForRemoteNotifications(withDeviceToken: Data([0x01, 0x02]))

            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))
            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: appDirectory)
            let registration = try await sidecar.connect(
                toPlugin: PushRegistrationMirror.pluginID,
                snapshot: PushRegistrationMirror.Snapshot.self,
                command: PushRegistrationMirror.Command.self
            )

            #expect(push.receiver.enabledCapabilities == [PushRegistrationMirror.pluginID])
            #expect(registration.snapshot == PushRegistrationMirror.Snapshot(sessionID: nil, registration: nil, environment: nil, settings: nil))
        }
    }
#endif
