// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import DebugDrawer
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
            let transport = DebugDrawerPluginTransport.direct(to: CookiesModel(jar: jar))
            let snapshots = transport.snapshots()
            transport.send(CookiesCommand(.reload))
            for await snapshot in snapshots where snapshot.allCookies.count == 2 {
                break
            }
            let sut = CookiesPluginView(transport: transport)
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
                transport.send(CookiesCommand(.delete(first.id)))
                for await snapshot in snapshots where snapshot.allCookies.count == 1 {
                    break
                }
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

        @Test("Refresh, the filter and a row's delete reach the model as commands, and a filter shows only its matches")
        func sendsCommands() throws {
            let shown = CookieFixtures.stored("session", domain: "api.example.com")
            let initial = CookiesSnapshot(
                contents: .cookies([shown, CookieFixtures.stored("theme", domain: "web.example.com", in: .webView)]), filter: "api"
            )
            var sent: [CookiesCommand] = []
            let sut = CookiesPluginView(transport: DebugDrawerPluginTransport(
                initial: initial, snapshots: AsyncStream { $0.finish() }, send: { sent.append($0) }
            ))
            let expectedLabel = "1 of 2 cookies"

            let view = try sut.inspect()
            let label = try view.find(text: expectedLabel).string()
            let rows = view.findAll(CookieRow.self).count
            try view.find(button: "Refresh").tap()
            try view.find(ViewType.TextField.self).setInput("web")
            try view.find(ViewType.Button.self, where: { try $0.accessibilityLabel().string() == "Delete session from URLSession" }).tap()

            #expect(label == expectedLabel)
            #expect(rows == 1)
            #expect(sent.count == 3)
            if case .reload = sent.first?.action {} else { Issue.record("Refresh sent \(String(describing: sent.first?.action))") }
            if case let .setFilter(filter) = sent.dropFirst().first?.action {
                #expect(filter == "web")
            } else {
                Issue.record("The filter sent \(String(describing: sent.dropFirst().first?.action))")
            }
            if case let .delete(id) = sent.last?.action {
                #expect(id == shown.id)
            } else {
                Issue.record("Delete sent \(String(describing: sent.last?.action))")
            }
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
