#if DEBUG
    @testable import DebugDrawerCookiesPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct CookiesModelTests {
        @Test("Both stores' cookies are listed, by domain, then name, then path, each with its store")
        func listsBothStores() async {
            let jar = FakeCookieJar([
                CookieFixtures.stored("theme", domain: "web.example.com", in: .webView),
                CookieFixtures.stored("session", domain: "api.example.com"),
                CookieFixtures.stored("csrf", domain: "web.example.com", in: .webView)
            ])
            let sut = CookiesModel(jar: jar)
            let expected = [
                StoredCookie.ID(store: .urlSession, name: "session", domain: "api.example.com", path: "/"),
                StoredCookie.ID(store: .webView, name: "csrf", domain: "web.example.com", path: "/"),
                StoredCookie.ID(store: .webView, name: "theme", domain: "web.example.com", path: "/")
            ]

            await sut.reload()

            let actual = sut.allCookies.map(\.id)
            #expect(actual == expected)
        }

        @Test("A row is identified by its store, name, domain and path, so the same cookie in both stores is two rows")
        func identityIncludesStore() async {
            let jar = FakeCookieJar([
                CookieFixtures.stored("session", in: .urlSession),
                CookieFixtures.stored("session", in: .webView),
                CookieFixtures.stored("session", path: "/admin", in: .urlSession),
                CookieFixtures.stored("session", domain: "other.example.com", in: .urlSession)
            ])
            let sut = CookiesModel(jar: jar)
            let expectedCount = 4

            await sut.reload()

            let actual = Set(sut.allCookies.map(\.id))
            #expect(actual.count == expectedCount)
        }

        @Test("A cookie with the same name, domain and path as another but a different value keeps the same identity")
        func identityIgnoresValue() {
            let before = CookieFixtures.stored("session", value: "old")
            let after = CookieFixtures.stored("session", value: "new")

            let actual = before.id == after.id

            #expect(actual)
        }

        @Test("Deleting a cookie deletes it from the store it is in, and leaves the same cookie in the other store")
        func deleteFromItsStore() async {
            let webView = CookieFixtures.stored("session", in: .webView)
            let jar = FakeCookieJar([CookieFixtures.stored("session", in: .urlSession), webView])
            let sut = CookiesModel(jar: jar)
            await sut.reload()
            let expectedDeleted = [webView.id]
            let expectedLeft = [StoredCookie.ID(store: .urlSession, name: "session", domain: "example.com", path: "/")]

            await sut.delete(webView)

            #expect(jar.deleted == expectedDeleted)
            #expect(sut.allCookies.map(\.id) == expectedLeft)
        }

        @Test("Delete All deletes only the cookies the filter shows, each from its own store")
        func deleteShownOnly() async {
            let jar = FakeCookieJar([
                CookieFixtures.stored("session", domain: "api.example.com"),
                CookieFixtures.stored("session", domain: "web.example.com", in: .webView),
                CookieFixtures.stored("theme", domain: "web.example.com", in: .webView)
            ])
            let sut = CookiesModel(jar: jar)
            await sut.reload()
            sut.filter = "SESSION"
            let expectedDeleted = [
                StoredCookie.ID(store: .urlSession, name: "session", domain: "api.example.com", path: "/"),
                StoredCookie.ID(store: .webView, name: "session", domain: "web.example.com", path: "/")
            ]
            let expectedLeft = [StoredCookie.ID(store: .webView, name: "theme", domain: "web.example.com", path: "/")]

            await sut.deleteShown()

            #expect(jar.deleted == expectedDeleted)
            #expect(sut.allCookies.map(\.id) == expectedLeft)
        }

        @Test("With no filter, Delete All deletes every cookie in both stores")
        func deleteAllUnfiltered() async {
            let jar = FakeCookieJar([
                CookieFixtures.stored("session", domain: "api.example.com"),
                CookieFixtures.stored("theme", domain: "web.example.com", in: .webView)
            ])
            let sut = CookiesModel(jar: jar)
            await sut.reload()
            let expectedDeletes = 2

            await sut.deleteShown()

            #expect(jar.deleted.count == expectedDeletes)
            #expect(sut.allCookies.isEmpty)
        }

        @Test("A filter that matches nothing makes Delete All delete nothing")
        func deleteShownNoMatches() async {
            let jar = FakeCookieJar([CookieFixtures.stored("session")])
            let sut = CookiesModel(jar: jar)
            await sut.reload()
            sut.filter = "nothing-matches"

            await sut.deleteShown()

            #expect(jar.deleted.isEmpty)
            #expect(sut.allCookies.count == 1)
        }

        @Test("The count is the cookies the filter shows, of every cookie in both stores")
        func countFollowsFilter() async {
            let jar = FakeCookieJar([
                CookieFixtures.stored("session", domain: "api.example.com"),
                CookieFixtures.stored("theme", domain: "web.example.com", in: .webView),
                CookieFixtures.stored("csrf", domain: "web.example.com", in: .webView)
            ])
            let sut = CookiesModel(jar: jar)
            await sut.reload()
            let expectedUnfiltered = CookieCount(shown: 3, total: 3)
            let expectedFiltered = CookieCount(shown: 2, total: 3)

            let unfiltered = sut.count
            sut.filter = "web."
            let actual = sut.count

            #expect(unfiltered == expectedUnfiltered)
            #expect(actual == expectedFiltered)
        }

        @Test("Before the stores are read there are no cookies, and the count is zero")
        func unread() {
            let sut = CookiesModel(jar: FakeCookieJar([CookieFixtures.stored("session")]))
            let expected = CookieCount(shown: 0, total: 0)

            let actual = sut.count

            #expect(actual == expected)
            #expect(sut.allCookies.isEmpty)
        }
    }
#endif
