// The Notifications capability module isn't built for watchOS, so neither is the kit's plugin for it.
#if DEBUG && os(macOS)
    import DebugDrawer
    import DebugDrawerNotifications
    @testable import DebugDrawerSidecarKit
    import Foundation
    import Testing
    import ViewInspector

    // The Push Registration plugin as a function of the capability's snapshot.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SidecarPushRegistrationTests {
        @Test("A registered app shows its token, the APNs server and source, and its settings; Refresh sends refresh")
        func registeredShowsToken() throws {
            let snapshot = PushRegistrationMirror.Snapshot(
                sessionID: UUID(), registration: .registered(deviceToken: "a1b2c3"),
                environment: PushEnvironment(server: .sandbox, source: .entitlement),
                settings: NotificationSettings(authorization: .authorized, items: [.init(name: "Alerts", value: "Enabled")])
            )
            var sent: [PushRegistrationMirror.Command] = []
            let sut = PushRegistrationView(snapshot: snapshot) { sent.append($0) }

            try sut.inspect().find(button: "Refresh").tap()

            #expect(sent == [.refresh])
            #expect(throws: Never.self) { try sut.inspect().find(text: "a1b2c3") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "Sandbox (api.sandbox.push.apple.com)") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "Code signature entitlement") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "Enabled") }
        }

        @Test("A failed registration shows the failure; settings not read yet read Reading…")
        func failedRegistration() throws {
            let snapshot = PushRegistrationMirror.Snapshot(
                sessionID: UUID(), registration: .failed(message: "no valid aps-environment"), environment: nil, settings: nil
            )
            let sut = PushRegistrationView(snapshot: snapshot) { _ in }

            #expect(throws: Never.self) { try sut.inspect().find(text: "no valid aps-environment") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "Not signed for push") }
            #expect(throws: Never.self) { try sut.inspect().find(text: "Reading…") }
        }

        @Test("With no registration served the plugin says why: no session, or a grant that doesn't list it")
        func emptyStates() throws {
            let outside = PushRegistrationMirror.Snapshot(sessionID: nil, registration: nil, environment: nil, settings: nil)
            let ungranted = PushRegistrationMirror.Snapshot(sessionID: UUID(), registration: nil, environment: nil, settings: nil)
            let noSession = PushRegistrationView(snapshot: outside) { _ in }
            let notGranted = PushRegistrationView(snapshot: ungranted) { _ in }

            #expect(throws: Never.self) { try noSession.inspect().find(text: "The app shows its device token only during a session.") }
            #expect(throws: Never.self) { try notGranted.inspect().find(text: "This session's grant doesn't list push registration.") }
        }

        @Test("The shipped Push Registration plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.pushRegistration

            #expect([sut.id, sut.title, sut.icon] == [PushRegistrationMirror.pluginID, "Push Registration", "app.badge"])
        }
    }
#endif
