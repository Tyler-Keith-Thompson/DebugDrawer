#if DEBUG
    @testable import DebugDrawerNotificationsPlugin
    import Foundation
    import Testing
    import UserNotifications

    // Building content asks the notification center nothing, so it runs in a test runner without
    // an app bundle.
    @Suite
    struct NotificationContentTests {
        @Test("A payload becomes content with its alert, badge, sound, category, thread and levels, and itself as userInfo")
        func content() throws {
            let text = """
            {"aps": {"alert": {"title": "Shipped", "subtitle": "Today", "body": "On its way"}, "badge": 2, "sound": "chime.caf", \
            "category": "ORDER", "thread-id": "orders", "target-content-id": "order-7", "interruption-level": "passive", \
            "relevance-score": 0.25}, "orderID": 7}
            """
            let payload = try NotificationPayload(parsing: text)

            let actual = UNMutableNotificationContent(payload)

            #expect(actual.title == "Shipped")
            #expect(actual.subtitle == "Today")
            #expect(actual.body == "On its way")
            #expect(actual.badge == 2)
            #expect(actual.sound == UNNotificationSound(named: UNNotificationSoundName("chime.caf")))
            #expect(actual.categoryIdentifier == "ORDER")
            #expect(actual.threadIdentifier == "orders")
            #expect(actual.targetContentIdentifier == "order-7")
            #expect(actual.interruptionLevel == .passive)
            #expect(actual.relevanceScore == 0.25)
            #expect(actual.userInfo["orderID"] as? Int == 7)
            #expect((actual.userInfo["aps"] as? [String: Any])?["category"] as? String == "ORDER")
        }

        @Test("A payload without a badge or sound leaves both unset, and the default sound is the system's")
        func defaults() throws {
            let silent = try NotificationPayload(parsing: #"{"aps": {"alert": "Hi"}}"#)
            let withDefault = try NotificationPayload(parsing: #"{"aps": {"alert": "Hi", "sound": "default"}}"#)

            let silentContent = UNMutableNotificationContent(silent)
            let defaultContent = UNMutableNotificationContent(withDefault)

            #expect(silentContent.badge == nil)
            #expect(silentContent.sound == nil)
            #expect(silentContent.interruptionLevel == .active)
            #expect(defaultContent.sound == .default)
        }

        #if os(iOS)
            @Test("On iOS, a critical sound is a critical one, at its volume")
            func criticalSound() throws {
                let payload = try NotificationPayload(parsing: #"{"aps": {"alert": "Hi", "sound": {"critical": 1, "volume": 0.5}}}"#)

                let actual = UNMutableNotificationContent(payload).sound

                #expect(actual == .defaultCriticalSound(withAudioVolume: 0.5))
            }
        #elseif os(macOS)
            @Test("On macOS, which has no critical sounds, a critical sound is the default one")
            func criticalSound() throws {
                let payload = try NotificationPayload(parsing: #"{"aps": {"alert": "Hi", "sound": {"critical": 1, "volume": 0.5}}}"#)

                let actual = UNMutableNotificationContent(payload).sound

                #expect(actual == .default)
            }
        #endif
    }
#endif
