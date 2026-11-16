// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import DebugDrawer
    @testable import DebugDrawerNotificationsPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NotificationsViewTests {
        @Test("A reported token shows as hexadecimal with Copy Token when the rules don't mask it")
        func token() throws {
            let sut = DeviceTokenSection(registration: .registered(deviceToken: Data([0x0A, 0xBC, 0xDE])), redaction: .none)

            let token = try sut.inspect().find(text: "0abcde").string()
            let copy = try sut.inspect().find(button: "Copy Token").labelView().text().string()

            #expect(token == "0abcde")
            #expect(copy == "Copy Token")
        }

        @Test("Under the standard rules the token is masked on screen until revealed, and Copy Token copies the token itself")
        func maskedToken() throws {
            let sut = DeviceTokenSection(registration: .registered(deviceToken: Data([0x0A, 0xBC, 0xDE])), redaction: .standard)

            let shown = try sut.inspect().find(text: DebugDrawerRedaction.mask).string()
            let reveal = try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Reveal value" }

            #expect(shown == DebugDrawerRedaction.mask)
            #expect(throws: (any Error).self) { try sut.inspect().find(text: "0abcde") }
            #expect(try reveal.accessibilityLabel().string() == "Reveal value")
        }

        @Test("With no token reported the section says how to forward one; a failure shows its reason")
        func noToken() throws {
            let none = DeviceTokenSection(registration: .notRegistered, redaction: .standard)
            let failed = DeviceTokenSection(registration: .failed(message: "no valid aps-environment entitlement"), redaction: .standard)

            let hint = try none.inspect().find(ViewType.Text.self) { try $0.string().hasPrefix("None reported.") }.string()
            let failure = try failed.inspect().find(text: "Registering failed: no valid aps-environment entitlement").string()

            #expect(hint.contains("PushNotifications.didRegisterForRemoteNotifications(withDeviceToken:)"))
            #expect(failure == "Registering failed: no valid aps-environment entitlement")
            #expect(throws: (any Error).self) { try none.inspect().find(button: "Copy Token") }
        }

        @Test("Authorization shows the status and each setting; Request shows only while undecided, and Refresh always")
        func authorization() throws {
            var requested = 0
            var refreshed = 0
            let settings = NotificationSettings(authorization: .notDetermined, items: [.init(name: "Alerts", value: "Not Supported")])
            let undecided = AuthorizationSection(settings: settings, request: .idle, onRequest: { requested += 1 }, onRefresh: { refreshed += 1 })
            let decided = AuthorizationSection(
                settings: NotificationSettings(authorization: .authorized, items: []), request: .idle, onRequest: {}, onRefresh: {}
            )

            let status = try undecided.inspect().find(text: "Notifications — Not Asked").string()
            let alerts = try undecided.inspect().find(text: "Not Supported").string()
            try undecided.inspect().find(button: "Request").tap()
            try undecided.inspect().find(button: "Refresh").tap()

            #expect(status == "Notifications — Not Asked")
            #expect(alerts == "Not Supported")
            #expect(requested == 1)
            #expect(refreshed == 1)
            #expect(throws: (any Error).self) { try decided.inspect().find(button: "Request") }
        }

        @Test("While the prompt is up Asking shows in place of Request; a failed request shows its reason")
        func authorizationRequest() throws {
            let settings = NotificationSettings(authorization: .notDetermined, items: [])
            let asking = AuthorizationSection(settings: settings, request: .requesting, onRequest: {}, onRefresh: {})
            let failed = AuthorizationSection(settings: settings, request: .failed(message: "Not allowed"), onRequest: {}, onRefresh: {})

            let progress = try asking.inspect().find(text: "Asking…").string()
            let failure = try failed.inspect().find(text: "Asking failed: Not allowed").string()

            #expect(progress == "Asking…")
            #expect(failure == "Asking failed: Not allowed")
            #expect(throws: (any Error).self) { try asking.inspect().find(button: "Request") }
        }

        @Test("A valid draft enables Send, which sends; a draft that isn't a payload shows why and disables Send")
        func composer() throws {
            var sent = 0
            let valid = PayloadComposer(
                draft: .constant(#"{"aps": {"alert": "Hi"}}"#), delay: .constant(.now), sendState: .idle,
                authorization: .authorized, onSend: { sent += 1 }
            )
            let invalid = PayloadComposer(
                draft: .constant(#"{"alert": "Hi"}"#), delay: .constant(.now), sendState: .idle, authorization: .authorized, onSend: {}
            )

            try valid.inspect().find(button: "Send").tap()
            let isValidDisabled = try valid.inspect().find(button: "Send").isDisabled()
            let error = try invalid.inspect().find(text: "The payload has no aps dictionary.").string()
            let isInvalidDisabled = try invalid.inspect().find(button: "Send").isDisabled()

            #expect(sent == 1)
            #expect(!isValidDisabled)
            #expect(error == "The payload has no aps dictionary.")
            #expect(isInvalidDisabled)
        }

        @Test("Typing into the editor changes the draft")
        func typing() throws {
            var draft = ""
            let binding = Binding(get: { draft }, set: { draft = $0 })
            let sut = PayloadComposer(draft: binding, delay: .constant(.now), sendState: .idle, authorization: .authorized, onSend: {})

            try sut.inspect().find(ViewType.TextEditor.self).setInput(#"{"aps": {}}"#)

            #expect(draft == #"{"aps": {}}"#)
        }

        @Test("The notes on how a local notification differs show under a valid draft")
        func notes() throws {
            let sut = PayloadComposer(
                draft: .constant(#"{"aps": {"content-available": 1}}"#), delay: .constant(.now), sendState: .idle,
                authorization: .authorized, onSend: {}
            )

            let note = try sut.inspect().find(ViewType.Text.self) { try $0.string().hasPrefix("content-available asks") }.string()

            #expect(note.contains("application(_:didReceiveRemoteNotification:fetchCompletionHandler:)"))
        }

        @Test("Undecided, Send asks first; denied, a note says nothing will show")
        func composerAuthorization() throws {
            let undecided = PayloadComposer(
                draft: .constant(#"{"aps": {"alert": "Hi"}}"#), delay: .constant(.now), sendState: .idle, authorization: .notDetermined, onSend: {}
            )
            let denied = PayloadComposer(
                draft: .constant(#"{"aps": {"alert": "Hi"}}"#), delay: .constant(.now), sendState: .idle, authorization: .denied, onSend: {}
            )
            let expected = "Notifications are denied: the system accepts what is sent and shows nothing."

            let ask = try undecided.inspect().find(button: "Ask and Send").labelView().text().string()
            let note = try denied.inspect().find(text: expected).string()

            #expect(ask == "Ask and Send")
            #expect(note == expected)
        }

        @Test("After a send the identifier shows, with when it arrives; a refusal shows its reason")
        func sendOutcome() throws {
            let draft = #"{"aps": {"alert": "Hi"}}"#
            let sent = PayloadComposer(
                draft: .constant(draft), delay: .constant(.fiveSeconds), sendState: .sent(identifier: "debugdrawer-1", delay: .fiveSeconds),
                authorization: .authorized, onSend: {}
            )
            let refused = PayloadComposer(
                draft: .constant(draft), delay: .constant(.now), sendState: .failed(message: "Not allowed"), authorization: .authorized, onSend: {}
            )

            let sentText = try sent.inspect().find(text: "Sent as debugdrawer-1, to arrive in 5 sec.").string()
            let refusedText = try refused.inspect().find(text: "The system refused it: Not allowed").string()

            #expect(sentText == "Sent as debugdrawer-1, to arrive in 5 sec.")
            #expect(refusedText == "The system refused it: Not allowed")
        }

        @Test("A pending notification shows its title, body, identifier and trigger, and Remove removes that one")
        func pendingRow() throws {
            var removed: [String] = []
            let notification = ListedNotification(
                id: "order-7", title: "Shipped", body: "On its way", categoryIdentifier: "ORDER",
                trigger: .timeInterval(seconds: 30, repeats: false, next: nil)
            )
            let sut = NotificationListSection(
                kind: .pending, notifications: [notification], redaction: .standard, onRemove: { removed.append($0) }, onRemoveAll: {}
            )

            let heading = try sut.inspect().find(text: "Pending (1)").string()
            let title = try sut.inspect().find(text: "Shipped").string()
            let body = try sut.inspect().find(text: "On its way").string()
            let identifier = try sut.inspect().find(text: "order-7").string()
            let details = try sut.inspect().find(text: "After 30 sec · category ORDER").string()
            try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Remove Shipped" }.tap()

            #expect(heading == "Pending (1)")
            #expect(title == "Shipped")
            #expect(body == "On its way")
            #expect(identifier == "order-7")
            #expect(details == "After 30 sec · category ORDER")
            #expect(removed == ["order-7"])
        }

        @Test("A delivered notification shows when it was delivered, and its userInfo masked under the rules")
        func deliveredRow() throws {
            let notification = ListedNotification(
                id: "order-7", title: "Shipped", trigger: .push, deliveredAt: Date(timeIntervalSince1970: 1_800_000_000),
                userInfo: UserInfoText(["authToken": "secret"])
            )
            let sut = NotificationListSection(
                kind: .delivered, notifications: [notification], redaction: .standard, onRemove: { _ in }, onRemoveAll: {}
            )

            // An offline inspect() reads the default locale and time zone, so only the year is
            // pinned; the snapshots pin the rest in a fixed locale.
            let delivered = try sut.inspect()
                .find(ViewType.Text.self) { try $0.string().hasPrefix("Delivered ") && $0.string().contains("2027") }
                .string()
            let userInfo = try sut.inspect().find(ViewType.Text.self) { try $0.string().contains("authToken") }.string()

            #expect(delivered.contains("2027"))
            #expect(userInfo.contains(DebugDrawerRedaction.mask))
            #expect(!userInfo.contains("secret"))
        }

        @Test("Remove All removes the list; an empty list says so and offers no Remove All")
        func removeAll() throws {
            var removedAll = 0
            let full = NotificationListSection(
                kind: .delivered, notifications: [ListedNotification(id: "a", title: "One")], redaction: .standard,
                onRemove: { _ in }, onRemoveAll: { removedAll += 1 }
            )
            let empty = NotificationListSection(kind: .pending, notifications: [], redaction: .standard, onRemove: { _ in }, onRemoveAll: {})

            try full.inspect().find(button: "Remove All").tap()
            let emptyText = try empty.inspect().find(text: "No pending notifications.").string()

            #expect(removedAll == 1)
            #expect(emptyText == "No pending notifications.")
            #expect(throws: (any Error).self) { try empty.inspect().find(button: "Remove All") }
        }

        @Test("Before the first read the view says it is reading, and shows the token section alone")
        func loading() throws {
            let sut = NotificationsView(
                registration: .notRegistered, center: .loading, authorizationRequest: .idle, sendState: .idle,
                draft: .constant(""), delay: .constant(.now), redaction: .standard, actions: NotificationsActions()
            )

            let reading = try sut.inspect().find(text: "Reading the notification center…").string()

            #expect(reading == "Reading the notification center…")
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Refresh") }
        }

        @Test("Every control names what it acts on for VoiceOver")
        func accessibilityLabels() throws {
            let snapshot = NotificationCenterSnapshot(
                settings: NotificationSettings(authorization: .notDetermined, items: []),
                pending: [ListedNotification(id: "a", title: "One")],
                delivered: [ListedNotification(id: "b", body: "Two")]
            )
            let sut = NotificationsView(
                registration: .notRegistered, center: .loaded(snapshot), authorizationRequest: .idle, sendState: .idle,
                draft: .constant(#"{"aps": {"alert": "Hi"}}"#), delay: .constant(.now), redaction: .standard, actions: NotificationsActions()
            )
            let expected = [
                "Request notification access", "Refresh notifications", "Send the payload as a local notification",
                "Remove One", "Remove all pending notifications", "Remove Two", "Remove all delivered notifications"
            ]

            let actual = try sut.inspect().findAll(ViewType.Button.self).map { try $0.accessibilityLabel().string() }
            let editor = try sut.inspect().find(ViewType.TextEditor.self).accessibilityLabel().string()
            let picker = try sut.inspect().find(ViewType.Picker.self).accessibilityLabel().string()

            #expect(actual == expected)
            #expect(editor == "APNs payload")
            #expect(picker == "When to deliver")
        }
    }
#endif
