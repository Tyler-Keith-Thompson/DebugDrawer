#if DEBUG
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import Testing

    @Suite
    struct ActivityDraftTests {
        @Test("A draft with a type and valid rows is ready to send as that activity, its rows in order")
        func ready() {
            let sut = ActivityDraft(activityType: " com.example.app.viewOrder ", fields: [
                UserInfoField(key: "orderID", kind: .number, text: "42"),
                UserInfoField(key: "total", kind: .number, text: "9.5"),
                UserInfoField(key: "note", kind: .string, text: ""),
                UserInfoField(key: "gift", kind: .boolean, isOn: true)
            ])
            let expected = DeepLinkActivity(activityType: "com.example.app.viewOrder", webpageURL: nil, userInfo: [
                UserInfoEntry(key: "orderID", value: .integer(42)),
                UserInfoEntry(key: "total", value: .double(9.5)),
                UserInfoEntry(key: "note", value: .string("")),
                UserInfoEntry(key: "gift", value: .bool(true))
            ])

            let actual = sut.validation

            #expect(actual == .ready(expected))
        }

        @Test("A draft with no type is incomplete, and says nothing")
        func incomplete() {
            let sut = ActivityDraft(activityType: "  ", fields: [UserInfoField(key: "id", text: "1")])

            let actual = sut.validation

            #expect(actual == .incomplete)
        }

        @Test("A row with no key, a repeated key or a number that isn't one makes the draft invalid, saying which")
        func invalid() {
            let missingKey = ActivityDraft(activityType: "a", fields: [UserInfoField(key: "", text: "x")])
            let repeated = ActivityDraft(activityType: "a", fields: [UserInfoField(key: "id", text: "1"), UserInfoField(key: "id", text: "2")])
            let notANumber = ActivityDraft(activityType: "a", fields: [UserInfoField(key: "count", kind: .number, text: "4 2")])

            #expect(missingKey.validation == .invalid("A row has no key"))
            #expect(repeated.validation == .invalid("“id” is used twice"))
            #expect(notANumber.validation == .invalid("“count” isn't a number"))
        }

        @Test("A number row reads a whole number as an integer, a fraction as a double, and refuses an empty or infinite one")
        func numberParsing() {
            func value(_ text: String) -> UserInfoValue? {
                UserInfoField(key: "n", kind: .number, text: text).value
            }

            #expect(value("-7") == .integer(-7))
            #expect(value(" 0 ") == .integer(0))
            #expect(value("1e3") == .double(1000))
            #expect(value("0.25") == .double(0.25))
            #expect(value("") == nil)
            #expect(value("inf") == nil)
            #expect(value("nan") == nil)
        }

        @Test("A draft made from an activity edits the same type and values")
        func roundTrip() {
            let activity = DeepLinkActivity(activityType: "com.example.app.viewOrder", webpageURL: nil, userInfo: [
                UserInfoEntry(key: "orderID", value: .integer(42)),
                UserInfoEntry(key: "total", value: .double(9.5)),
                UserInfoEntry(key: "title", value: .string("Order")),
                UserInfoEntry(key: "gift", value: .bool(false))
            ])

            let actual = ActivityDraft(activity).validation

            #expect(actual == .ready(activity))
        }

        @Test("An http or https URL suggests Universal Link; any other URL, or none, suggests Open URL")
        func suggestedMode() {
            #expect(DeepLinkMode.suggested(for: "https://example.com/path") == .universalLink)
            #expect(DeepLinkMode.suggested(for: " HTTP://example.com ") == .universalLink)
            #expect(DeepLinkMode.suggested(for: "myapp://deeplink/screen") == .open)
            #expect(DeepLinkMode.suggested(for: "https://") == .open)
            #expect(DeepLinkMode.suggested(for: "") == .open)
        }
    }
#endif
