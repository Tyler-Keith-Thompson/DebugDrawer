// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DeepLinkViewTests {
        @Test("An https URL in the field offers Continue, which sends it as a universal link")
        func httpsContinues() throws {
            var sent: [DeepLinkActivity] = []
            let sut = DeepLinkForm(
                urlText: .constant("https://example.com/orders/42"), presets: [],
                onOpen: { _ in }, onContinue: { sent.append($0) }, onClear: {}
            )
            let url = try #require(URL(string: "https://example.com/orders/42"))
            let expected = [DeepLinkActivity.universalLink(url)]

            try sut.inspect().find(button: "Continue").tap()

            #expect(sent == expected)
        }

        @Test("A custom-scheme URL in the field offers Open and no Continue")
        func customSchemeOpens() throws {
            let sut = DeepLinkForm(
                urlText: .constant("myapp://orders/42"), presets: [], onOpen: { _ in }, onContinue: { _ in }, onClear: {}
            )

            let open = try? sut.inspect().find(ViewType.Link.self)
            let continueButton = try? sut.inspect().find(button: "Continue")

            #expect(open != nil)
            #expect(continueButton == nil)
        }

        @Test("In Universal Link mode, a URL that isn't http or https can't be continued")
        func universalLinkNeedsWebURL() throws {
            var sent: [DeepLinkActivity] = []
            let sut = DeepLinkForm(
                urlText: .constant("myapp://orders/42"), presets: [], mode: .universalLink,
                onOpen: { _ in }, onContinue: { sent.append($0) }, onClear: {}
            )

            let button = try sut.inspect().find(button: "Continue")

            #expect(button.isDisabled())
            #expect(sent.isEmpty)
        }

        @Test("In Activity mode, Continue sends the type and the userInfo rows as an activity")
        func activityContinues() throws {
            var sent: [DeepLinkActivity] = []
            let draft = ActivityDraft(activityType: "com.example.app.viewOrder", fields: [
                UserInfoField(key: "orderID", kind: .number, text: "42"),
                UserInfoField(key: "gift", kind: .boolean, isOn: true)
            ])
            let sut = DeepLinkForm(
                urlText: .constant(""), presets: [], mode: .activity, draft: draft,
                onOpen: { _ in }, onContinue: { sent.append($0) }, onClear: {}
            )
            let expected = [DeepLinkActivity(activityType: "com.example.app.viewOrder", webpageURL: nil, userInfo: [
                UserInfoEntry(key: "orderID", value: .integer(42)),
                UserInfoEntry(key: "gift", value: .bool(true))
            ])]

            try sut.inspect().find(button: "Continue").tap()

            #expect(sent == expected)
        }

        @Test("A number row that isn't a number says so and disables Continue")
        func invalidDraft() throws {
            let draft = ActivityDraft(activityType: "com.example.app.viewOrder", fields: [UserInfoField(key: "count", kind: .number, text: "four")])
            let sut = DeepLinkForm(
                urlText: .constant(""), presets: [], mode: .activity, draft: draft, onOpen: { _ in }, onContinue: { _ in }, onClear: {}
            )

            let view = try sut.inspect()

            #expect(try view.find(button: "Continue").isDisabled())
            #expect(throws: Never.self) { try view.find(text: "“count” isn't a number") }
        }

        @Test("Picking Activity shows the type field and User Info, and Add Key adds an empty row")
        func addKey() async throws {
            let sut = DeepLinkForm(urlText: .constant(""), presets: [], onOpen: { _ in }, onContinue: { _ in }, onClear: {})
            var typeFieldBefore = true
            var typeFieldAfter = false
            var rowsAfterAdding = 0

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    typeFieldBefore = (try? view.find(ViewType.TextField.self) { try $0.labelView().text().string() == "Activity type" }) != nil
                    try view.find(ViewType.Picker.self).select(value: DeepLinkMode.activity)
                }
                try await sut.inspection.inspect { view in
                    typeFieldAfter = (try? view.find(ViewType.TextField.self) { try $0.labelView().text().string() == "Activity type" }) != nil
                    try view.find(button: "Add Key").tap()
                }
                try await sut.inspection.inspect { view in
                    rowsAfterAdding = view.findAll(UserInfoFieldRow.self).count
                }
            }

            #expect(!typeFieldBefore)
            #expect(typeFieldAfter)
            #expect(rowsAfterAdding == 1)
        }

        @Test("Tapping a continued activity in the history puts its type and userInfo back in the form")
        func restoreActivity() async throws {
            var sent: [DeepLinkActivity] = []
            let activity = DeepLinkActivity(
                activityType: "com.example.app.viewOrder", webpageURL: nil, userInfo: [UserInfoEntry(key: "orderID", value: .integer(7))]
            )
            let sut = DeepLinkForm(
                urlText: .constant(""), presets: [], activities: [activity],
                onOpen: { _ in }, onContinue: { sent.append($0) }, onClear: {}
            )

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(text: "orderID = 7").find(ViewType.Button.self, relation: .parent).tap()
                }
                try await sut.inspection.inspect { view in
                    try view.find(button: "Continue").tap()
                }
            }

            #expect(sent == [activity])
        }

        @Test("Continued activities are listed under Activities, apart from the URLs under History")
        func historySections() throws {
            let url = try #require(URL(string: "https://example.com/a"))
            let sut = DeepLinkForm(
                urlText: .constant(""), presets: [], history: ["myapp://orders/42"], activities: [.universalLink(url)],
                onOpen: { _ in }, onContinue: { _ in }, onClear: {}
            )

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "History (1)") }
            #expect(throws: Never.self) { try view.find(text: "Activities (1)") }
            #expect(throws: Never.self) { try view.find(text: "Universal Link") }
            #expect(throws: Never.self) { try view.find(text: "https://example.com/a") }
        }

        @Test("With no handler and no delegate method, the form says to pass continueUserActivity:")
        func unhandledMessage() throws {
            let sut = DeepLinkForm(
                urlText: .constant("https://example.com/path"), outcome: .continued(.unhandled), presets: [],
                onOpen: { _ in }, onContinue: { _ in }, onClear: {}
            )

            let view = try sut.inspect()

            #expect(throws: Never.self) { try view.find(text: "This app has no handler: pass continueUserActivity: to installDeepLink") }
        }
    }
#endif
