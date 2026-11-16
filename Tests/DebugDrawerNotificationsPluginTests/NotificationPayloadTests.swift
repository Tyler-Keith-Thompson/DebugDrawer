#if DEBUG
    @testable import DebugDrawerNotificationsPlugin
    import Foundation
    import Testing

    @Suite
    struct NotificationPayloadTests {
        @Test("An alert dictionary gives the title, subtitle and body; badge, sound, category and thread come from aps")
        func alertDictionary() throws {
            let text = """
            {"aps": {"alert": {"title": "Order shipped", "subtitle": "Today", "body": "On its way"}, "badge": 3, "sound": "default", \
            "category": "ORDER", "thread-id": "orders", "target-content-id": "order-7"}}
            """

            let actual = try NotificationPayload(parsing: text)

            #expect(actual.title == "Order shipped")
            #expect(actual.subtitle == "Today")
            #expect(actual.body == "On its way")
            #expect(actual.badge == 3)
            #expect(actual.sound == .default)
            #expect(actual.categoryIdentifier == "ORDER")
            #expect(actual.threadIdentifier == "orders")
            #expect(actual.targetContentIdentifier == "order-7")
            #expect(actual.notes.isEmpty)
        }

        @Test("A string alert is the body alone")
        func alertString() throws {
            let text = #"{"aps": {"alert": "Your order shipped"}}"#

            let actual = try NotificationPayload(parsing: text)

            #expect(actual.title.isEmpty)
            #expect(actual.subtitle.isEmpty)
            #expect(actual.body == "Your order shipped")
            #expect(actual.badge == nil)
            #expect(actual.sound == nil)
        }

        @Test("userInfo is the whole payload: aps and every key beside it")
        func userInfo() throws {
            let text = #"{"aps": {"alert": "Hi"}, "orderID": 42, "deepLink": "app://orders/42", "nested": {"flag": true}}"#
            let expectedKeys = ["aps", "deepLink", "nested", "orderID"]

            let actual = try NotificationPayload(parsing: text).userInfo

            #expect(actual.keys.compactMap { $0 as? String }.sorted() == expectedKeys)
            #expect(actual["orderID"] as? Int == 42)
            #expect(actual["deepLink"] as? String == "app://orders/42")
            #expect((actual["nested"] as? [String: Any])?["flag"] as? Bool == true)
            #expect((actual["aps"] as? [String: Any])?["alert"] as? String == "Hi")
        }

        @Test("Two pastes of one payload with their keys in different orders are equal")
        func keyOrder() throws {
            let first = #"{"aps": {"alert": "Hi", "badge": 1}, "a": 1, "b": 2}"#
            let second = #"{"b": 2, "a": 1, "aps": {"badge": 1, "alert": "Hi"}}"#

            let expected = try NotificationPayload(parsing: first)
            let actual = try NotificationPayload(parsing: second)

            #expect(actual == expected)
        }

        @Test("Curly double quotes, as iOS's keyboard types them, are read as straight ones; curly quotes inside valid JSON stay")
        func curlyQuotes() throws {
            let typed = "{“aps”: {“alert”: “Hi”}}"
            let quoting = #"{"aps": {"alert": "She said “hi”"}}"#

            let typedBody = try NotificationPayload(parsing: typed).body
            let quotingBody = try NotificationPayload(parsing: quoting).body

            #expect(typedBody == "Hi")
            #expect(quotingBody == "She said “hi”")
        }

        @Test("A sound string other than default names a sound file")
        func namedSound() throws {
            let text = #"{"aps": {"alert": "Hi", "sound": "chime.caf"}}"#

            let actual = try NotificationPayload(parsing: text).sound

            #expect(actual == .named("chime.caf"))
        }

        @Test("A critical sound dictionary keeps its name and volume; its default name is the default critical sound")
        func criticalSound() throws {
            let named = #"{"aps": {"alert": "Hi", "sound": {"critical": 1, "name": "alarm.caf", "volume": 0.5}}}"#
            let unnamed = #"{"aps": {"alert": "Hi", "sound": {"critical": 1, "name": "default"}}}"#

            let namedSound = try NotificationPayload(parsing: named).sound
            let unnamedSound = try NotificationPayload(parsing: unnamed).sound

            #expect(namedSound == .critical(name: "alarm.caf", volume: 0.5))
            #expect(unnamedSound == .critical(name: nil, volume: nil))
        }

        @Test("A sound dictionary that isn't critical plays its named sound, or the default")
        func nonCriticalSoundDictionary() throws {
            let named = #"{"aps": {"alert": "Hi", "sound": {"critical": 0, "name": "chime.caf"}}}"#
            let unnamed = #"{"aps": {"alert": "Hi", "sound": {}}}"#

            let namedSound = try NotificationPayload(parsing: named).sound
            let unnamedSound = try NotificationPayload(parsing: unnamed).sound

            #expect(namedSound == .named("chime.caf"))
            #expect(unnamedSound == .default)
        }

        @Test("Localization keys stand in for missing text, shown as the key with a note each")
        func localizationKeys() throws {
            let text = #"{"aps": {"alert": {"title-loc-key": "ORDER_TITLE", "loc-key": "ORDER_BODY", "loc-args": ["7"]}}}"#

            let actual = try NotificationPayload(parsing: text)

            #expect(actual.title == "ORDER_TITLE")
            #expect(actual.body == "ORDER_BODY")
            #expect(actual.notes.count == 2)
            #expect(actual.notes.first?.hasPrefix("title-loc-key “ORDER_TITLE” is shown as the key") == true)
            #expect(actual.notes.last?.hasPrefix("loc-key “ORDER_BODY” is shown as the key") == true)
        }

        @Test("A localization key beside its text leaves the text and adds no note")
        func localizationKeyBesideText() throws {
            let text = #"{"aps": {"alert": {"title": "Shipped", "title-loc-key": "ORDER_TITLE", "body": "On its way"}}}"#

            let actual = try NotificationPayload(parsing: text)

            #expect(actual.title == "Shipped")
            #expect(actual.notes.isEmpty)
        }

        @Test("Interruption level and relevance score are read; an unknown level is an error")
        func interruptionLevel() throws {
            let text = #"{"aps": {"alert": "Hi", "interruption-level": "time-sensitive", "relevance-score": 0.75}}"#
            let unknown = #"{"aps": {"alert": "Hi", "interruption-level": "urgent"}}"#
            let expected = NotificationPayloadError.wrongType(key: "interruption-level", expected: "passive, active, time-sensitive or critical")

            let actual = try NotificationPayload(parsing: text)

            #expect(actual.interruptionLevel == .timeSensitive)
            #expect(actual.relevanceScore == 0.75)
            #expect(throws: expected) { try NotificationPayload(parsing: unknown) }
        }

        @Test("content-available and mutable-content each add a note on what a local notification doesn't do")
        func backgroundAndMutable() throws {
            let text = #"{"aps": {"content-available": 1, "mutable-content": 1}}"#

            let actual = try NotificationPayload(parsing: text).notes

            #expect(actual.count == 2)
            #expect(actual.first?.hasPrefix("content-available asks to wake the app") == true)
            #expect(actual.last?.hasPrefix("mutable-content asks for the app’s notification service extension") == true)
        }

        @Test("A payload with no title, subtitle or body notes that nothing will show")
        func blank() throws {
            let text = #"{"aps": {"badge": 2}}"#
            let expected = ["It has no title, subtitle or body, so the system shows nothing for it."]

            let actual = try NotificationPayload(parsing: text).notes

            #expect(actual == expected)
        }

        @Test("A payload over 4 KB notes that APNs would refuse it; one at 4 KB doesn't")
        func size() throws {
            func payload(bytes: Int) -> String {
                let prefix = #"{"aps": {"alert": "Hi"}, "padding": ""#
                let suffix = #""}"#
                return prefix + String(repeating: "x", count: bytes - prefix.utf8.count - suffix.utf8.count) + suffix
            }
            let atLimit = payload(bytes: 4096)
            let overLimit = payload(bytes: 4097)

            let atLimitNotes = try NotificationPayload(parsing: atLimit).notes
            let overLimitNotes = try NotificationPayload(parsing: overLimit).notes

            #expect(atLimit.utf8.count == 4096)
            #expect(atLimitNotes.isEmpty)
            #expect(overLimitNotes == ["It is 4097 bytes: APNs refuses a payload over 4096."])
        }

        @Test("Empty text, text that isn't JSON, JSON that isn't an object and an object without aps are each their own error")
        func structuralErrors() {
            let cases: [(String, NotificationPayloadError)] = [
                ("", .empty),
                ("  \n", .empty),
                ("{aps:", .notJSON),
                ("[1, 2]", .notAnObject),
                ("\"aps\"", .notAnObject),
                (#"{"alert": "Hi"}"#, .missingAPS),
                (#"{"aps": "Hi"}"#, .wrongType(key: "aps", expected: "an object"))
            ]

            for (text, expected) in cases {
                #expect(throws: expected) { try NotificationPayload(parsing: text) }
            }
        }

        @Test("A value of the wrong type names its key and what it must be")
        func wrongTypes() {
            let cases: [(String, NotificationPayloadError)] = [
                (#"{"aps": {"alert": 7}}"#, .wrongType(key: "alert", expected: "a string or an object")),
                (#"{"aps": {"alert": {"title": 7}}}"#, .wrongType(key: "title", expected: "a string")),
                (#"{"aps": {"badge": "3"}}"#, .wrongType(key: "badge", expected: "a whole number")),
                (#"{"aps": {"badge": 1.5}}"#, .wrongType(key: "badge", expected: "a whole number")),
                (#"{"aps": {"badge": null}}"#, .wrongType(key: "badge", expected: "a whole number")),
                (#"{"aps": {"sound": 1}}"#, .wrongType(key: "sound", expected: "a string or an object")),
                (#"{"aps": {"category": ["a"]}}"#, .wrongType(key: "category", expected: "a string")),
                (#"{"aps": {"relevance-score": "high"}}"#, .wrongType(key: "relevance-score", expected: "a number"))
            ]

            for (text, expected) in cases {
                #expect(throws: expected) { try NotificationPayload(parsing: text) }
            }
        }

        @Test("Each error says what is wrong in a sentence")
        func messages() {
            let errors: [NotificationPayloadError] = [
                .empty, .notJSON, .notAnObject, .missingAPS, .wrongType(key: "badge", expected: "a whole number")
            ]
            let expected = [
                "Paste an APNs payload: a JSON object with an aps dictionary.",
                "This isn’t valid JSON.",
                "The payload must be a JSON object.",
                "The payload has no aps dictionary.",
                "badge must be a whole number."
            ]

            let actual = errors.map(\.message)

            #expect(actual == expected)
        }

        @MainActor
        @Test("The starter payload in the editor parses, with nothing to note")
        func starter() throws {
            let actual = try NotificationPayload(parsing: NotificationsModel.starterPayload)

            #expect(actual.title == "Hello")
            #expect(actual.body == "Sent from the debug drawer")
            #expect(actual.notes.isEmpty)
        }
    }
#endif
