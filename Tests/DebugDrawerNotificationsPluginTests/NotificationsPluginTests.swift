#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerNotificationsPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct NotificationsPluginTests {
        @Test("The plugin is Notifications, in the App category, offers Refresh and Remove All, and adds to bug reports")
        func identity() {
            let model = NotificationsModel(
                registration: .notRegistered, client: FakeNotificationCenter(authorization: .authorized), changes: FakeNotificationChangeSource()
            )

            let sut = NotificationsPlugin(model: model)

            #expect(sut.id == "NotificationsPlugin")
            #expect(sut.title == "Notifications")
            #expect(sut.category == "App")
            #expect(sut.icon == "bell.badge")
            #expect(sut.actions.map(\.title) == ["Refresh notifications", "Remove pending notifications", "Remove delivered notifications"])
            #expect(AnyDebugDrawerPlugin(sut).contributesToReport)
        }

        @Test("The search actions remove every pending or delivered notification")
        func actions() {
            let center = FakeNotificationCenter(authorization: .authorized)
            let model = NotificationsModel(registration: .notRegistered, client: center, changes: FakeNotificationChangeSource())
            let sut = NotificationsPlugin(model: model)

            sut.actions[1].perform()
            sut.actions[2].perform()

            #expect(center.removedAllPending == 1)
            #expect(center.removedAllDelivered == 1)
        }

        @Test("The bug report gets notifications.txt: the token masked, the settings, and each notification with its masked userInfo")
        func report() throws {
            let snapshot = NotificationCenterSnapshot(
                settings: NotificationSettings(
                    authorization: .authorized, items: [.init(name: "Alerts", value: "On"), .init(name: "Badges", value: "Off")]
                ),
                pending: [ListedNotification(
                    id: "debugdrawer-1", title: "Later", trigger: .timeInterval(seconds: 30, repeats: false, next: nil),
                    userInfo: UserInfoText(["authToken": "secret", "orderID": 7])
                )],
                delivered: [ListedNotification(
                    id: "order-7", title: "Shipped", body: "On its way", categoryIdentifier: "ORDER", badge: 1,
                    trigger: .push, deliveredAt: Date(timeIntervalSince1970: 1_800_000_000)
                )]
            )
            let expected = """
            APNs device token: [REDACTED]
            Authorization: Allowed
              Alerts: On
              Badges: Off
            Pending (1):
              debugdrawer-1
                trigger: After 30 sec
                title: Later
                userInfo:
                  {
                    "authToken" : "[REDACTED]",
                    "orderID" : 7
                  }
            Delivered (1):
              order-7
                delivered: 2027-01-15T08:00:00Z
                title: Shipped
                body: On its way
                category: ORDER
                badge: 1
            """
            var actual = DebugDrawerReport()

            NotificationsPlugin.contribute(
                registration: .registered(deviceToken: Data([0xAB, 0xCD])), center: .loaded(snapshot), redaction: .standard, to: &actual
            )

            let file = try #require(actual.files.first)
            #expect(actual.files.map(\.name) == ["notifications.txt"])
            #expect(String(bytes: file.data, encoding: .utf8) == expected)
        }

        @Test("Without rules the token is in the report as hexadecimal; before the first read the center says so")
        func reportUnredacted() {
            let expected = """
            APNs device token: abcd
            Notification center: not read yet
            """

            let actual = NotificationsPlugin.text(registration: .registered(deviceToken: Data([0xAB, 0xCD])), center: .loading, redaction: .none)

            #expect(actual == expected)
        }

        @Test("The report says when nothing was reported and when registering failed")
        func reportRegistration() {
            let empty = NotificationCenterState.loaded(NotificationCenterSnapshot(
                settings: NotificationSettings(authorization: .notDetermined, items: []), pending: [], delivered: []
            ))
            let expectedNone = """
            APNs device token: none reported
            Authorization: Not Asked
            Pending (0):
            Delivered (0):
            """
            let expectedFailure = "APNs registration failed: no valid aps-environment entitlement"

            let none = NotificationsPlugin.text(registration: .notRegistered, center: empty, redaction: .standard)
            let failure = NotificationsPlugin.text(
                registration: .failed(message: "no valid aps-environment entitlement"), center: empty, redaction: .standard
            )

            #expect(none == expectedNone)
            #expect(failure.hasPrefix(expectedFailure))
        }
    }
#endif
