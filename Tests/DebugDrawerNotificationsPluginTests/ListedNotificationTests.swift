#if DEBUG
    import DebugDrawer
    import DebugDrawerNotifications
    @testable import DebugDrawerNotificationsPlugin
    import Foundation
    import Testing

    @Suite
    struct ListedNotificationTests {
        @Test("A device token reads as lowercase hexadecimal, two digits a byte")
        func hexadecimal() {
            let token = Data([0x00, 0x0F, 0xA0, 0xFF])

            let actual = token.hexadecimal

            #expect(actual == "000fa0ff")
        }

        @Test("An empty token reads as nothing")
        func emptyHexadecimal() {
            let actual = Data().hexadecimal

            #expect(actual.isEmpty)
        }

        @Test("userInfo that JSON holds is pretty-printed with sorted keys; empty userInfo is no text")
        func userInfoJSON() {
            let userInfo: [AnyHashable: Any] = ["b": 2, "a": ["c": "d"]]
            let expected = """
            {
              "a" : {
                "c" : "d"
              },
              "b" : 2
            }
            """

            let actual = UserInfoText(userInfo)
            let empty = UserInfoText([:])

            #expect(actual == UserInfoText(text: expected, isJSON: true))
            #expect(empty == UserInfoText(text: "", isJSON: false))
        }

        @Test("userInfo JSON can't hold, such as a date, is its description, and isn't JSON")
        func userInfoDescription() {
            let userInfo: [AnyHashable: Any] = ["when": Date(timeIntervalSince1970: 0)]

            let actual = UserInfoText(userInfo)

            #expect(!actual.isJSON)
            #expect(actual.text.contains("when"))
        }

        @Test("Sensitive userInfo values are masked under the rules and the rest kept; text that isn't JSON is masked whole")
        func redactedUserInfo() {
            func notification(_ userInfo: UserInfoText) -> ListedNotification {
                ListedNotification(
                    id: "a", title: "", subtitle: "", body: "", categoryIdentifier: "", threadIdentifier: "", badge: nil,
                    trigger: .immediate, deliveredAt: nil, userInfo: userInfo
                )
            }
            let json = notification(UserInfoText(["authToken": "secret-value", "orderID": 7]))
            let description = notification(UserInfoText(text: "[when: 1970-01-01]", isJSON: false))
            let expected = """
            {
              "authToken" : "[REDACTED]",
              "orderID" : 7
            }
            """

            let actual = json.redactedUserInfo(.standard)
            let unmasked = json.redactedUserInfo(.none)
            let maskedDescription = description.redactedUserInfo(.standard)
            let plainDescription = description.redactedUserInfo(.none)

            #expect(actual == expected)
            #expect(unmasked == json.userInfo.text)
            #expect(maskedDescription == DebugDrawerRedaction.mask)
            #expect(plainDescription == "[when: 1970-01-01]")
        }

        @Test("A notification is named by its title, else its body, else its identifier")
        func displayName() {
            func notification(title: String, body: String) -> ListedNotification {
                ListedNotification(
                    id: "order-7", title: title, subtitle: "", body: body, categoryIdentifier: "", threadIdentifier: "", badge: nil,
                    trigger: .immediate, deliveredAt: nil, userInfo: UserInfoText([:])
                )
            }

            let actual = [
                notification(title: "Shipped", body: "On its way").displayName,
                notification(title: "", body: "On its way").displayName,
                notification(title: "", body: "").displayName
            ]

            #expect(actual == ["Shipped", "On its way", "order-7"])
        }

        @Test("Each trigger says what delivers it, with its next date in the given locale and time zone")
        func triggerText() throws {
            let locale = Locale(identifier: "en_US_POSIX")
            let timeZone = try #require(TimeZone(identifier: "UTC"))
            let next = Date(timeIntervalSince1970: 1_800_000_000)
            var components = DateComponents()
            components.hour = 9
            components.minute = 30
            let triggers: [NotificationTrigger] = [
                .immediate,
                .timeInterval(seconds: 5, repeats: false, next: nil),
                .timeInterval(seconds: 3660, repeats: true, next: next),
                .calendar(components, repeats: true, next: nil),
                .calendar(DateComponents(), repeats: false, next: nil),
                .location(region: "Office", repeats: false),
                .push,
                .other("UNCustomTrigger")
            ]
            let expected = [
                "Immediately",
                "After 5 sec",
                "Every 1 hr, 1 min, next Jan 15, 2027 at 8:00:00\u{202F}AM",
                "When hour 9, minute 30, repeating",
                "When any date",
                "At Office",
                "Push",
                "UNCustomTrigger"
            ]

            let actual = triggers.map { $0.text(locale: locale, timeZone: timeZone) }

            #expect(actual == expected)
        }
    }
#endif
