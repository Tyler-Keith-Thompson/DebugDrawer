// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawerCookiesPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct CookiesViewTests {
        @Test("Deleting an expanded cookie doesn't expand the cookie that takes its row")
        func expandedStateStaysWithItsCookie() async throws {
            let first = CookieFixtures.stored("a_session")
            let jar = FakeCookieJar([first, CookieFixtures.stored("b_theme")])
            let model = CookiesModel(jar: jar)
            await model.reload()
            let sut = CookiesPluginView(model: model)
            var firstAfterTap = ""
            var secondAfterDelete = ""
            var detailsAfterDelete = -1

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "a_session" }).tap()
                }
                try await sut.inspection.inspect { view in
                    firstAfterTap = try view.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "a_session" })
                        .accessibilityValue().string()
                }
                await model.delete(first)
                try await sut.inspection.inspect { view in
                    secondAfterDelete = try view.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "b_theme" })
                        .accessibilityValue().string()
                    detailsAfterDelete = view.findAll(CookieDetails.self).count
                }
            }

            #expect(firstAfterTap == "Expanded")
            #expect(secondAfterDelete == "Collapsed")
            #expect(detailsAfterDelete == 0)
        }

        @Test("A row names the store its cookie is in, and its delete button says which")
        func rowShowsStore() throws {
            let sut = CookieRow(
                stored: CookieFixtures.stored("session", in: .webView), redaction: .standard, isExpanded: false, toggle: {}, onDelete: {}
            )
            let expectedDelete = "Delete session from WKWebView"

            let store = try sut.inspect().find(text: "WKWebView").string()
            let delete = try sut.inspect().find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == expectedDelete })

            #expect(store == "WKWebView")
            #expect(try delete.accessibilityLabel().string() == expectedDelete)
        }

        @Test("Delete All asks in place first, and deletes only once Delete is pressed")
        func deleteAllAsksFirst() async throws {
            var deletes = 0
            let sut = CookiesToolbar(count: CookieCount(shown: 2, total: 5), refresh: {}, deleteAll: { deletes += 1 }, copy: {})
            var askedBefore = true
            var question = ""
            var deletesWhileAsking = -1
            var askedAfter = true

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    askedBefore = (try? view.find(CookiesDeleteConfirmation.self)) != nil
                    try view.find(button: "Delete All").tap()
                }
                try await sut.inspection.inspect { view in
                    question = try view.find(text: "Delete the 2 cookies the filter shows?").string()
                    deletesWhileAsking = deletes
                    try view.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "Delete the cookies shown" }).tap()
                }
                try await sut.inspection.inspect { view in
                    askedAfter = (try? view.find(CookiesDeleteConfirmation.self)) != nil
                }
            }

            #expect(!askedBefore)
            #expect(question == "Delete the 2 cookies the filter shows?")
            #expect(deletesWhileAsking == 0)
            #expect(deletes == 1)
            #expect(!askedAfter)
        }

        @Test("Cancel closes Delete All's question and deletes nothing")
        func deleteAllCancel() async throws {
            var deletes = 0
            let sut = CookiesToolbar(count: CookieCount(shown: 3, total: 3), refresh: {}, deleteAll: { deletes += 1 }, copy: {})
            var askedAfter = true

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    try view.find(button: "Delete All").tap()
                }
                try await sut.inspection.inspect { view in
                    try view.find(button: "Cancel").tap()
                }
                try await sut.inspection.inspect { view in
                    askedAfter = (try? view.find(CookiesDeleteConfirmation.self)) != nil
                }
            }

            #expect(!askedAfter)
            #expect(deletes == 0)
        }

        @Test("Delete All can't be pressed when the filter shows no cookies")
        func deleteAllDisabledWhenNoneShown() throws {
            let sut = CookiesToolbar(count: CookieCount(shown: 0, total: 4), refresh: {}, deleteAll: {}, copy: {})

            let actual = try sut.inspect().find(button: "Delete All").isDisabled()

            #expect(actual)
        }

        @Test("The toolbar's count follows the filter")
        func toolbarCount() throws {
            let sut = CookiesToolbar(count: CookieCount(shown: 3, total: 12), refresh: {}, deleteAll: {}, copy: {})
            let expected = "3 of 12 cookies"

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
        }
    }
#endif
