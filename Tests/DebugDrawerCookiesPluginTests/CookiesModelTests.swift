#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerCookiesPlugin
    import Foundation
    import Testing

    // The model is read and driven here as an out-of-process reader would: through its snapshot,
    // encoded and decoded, and commands, sent through a direct transport, with no view. Its cookie
    // stores are a hand-written fake; nothing touches HTTPCookieStorage or WebKit. Reads and
    // deletes land a hop after their command, so each test waits on the transport's stream of
    // snapshots for the one it expects.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct CookiesModelTests {
        @Test("A snapshot of both stores' cookies, with a filter, encodes to JSON and decodes equal")
        func snapshotRoundTrips() async throws {
            let secure = StoredCookie(
                name: "session", value: "a1b2c3", domain: "api.example.com", path: "/v1", store: .urlSession,
                isSecure: true, isHTTPOnly: true, expiresDate: Date(timeIntervalSinceReferenceDate: 820_000_000.5)
            )
            let model = CookiesModel(jar: FakeCookieJar([secure, CookieFixtures.stored("theme", domain: "web.example.com", in: .webView)]))
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = transport.snapshots()
            transport.send(CookiesCommand(.reload))
            transport.send(CookiesCommand(.setFilter("api")))
            var read: CookiesSnapshot?
            for await snapshot in snapshots where snapshot.allCookies.count == 2 {
                read = snapshot
                break
            }
            let expected = try #require(read)

            let encoded = try JSONEncoder().encode(expected)
            let actual = try JSONDecoder().decode(CookiesSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.filter == "api")
            #expect(actual.shownCookies == [secure])
            #expect(actual.count == CookieCount(shown: 1, total: 2))
        }

        @Test("A snapshot before the stores are read encodes to JSON and decodes equal, with no cookies")
        func unreadSnapshotRoundTrips() throws {
            let sut = CookiesModel(jar: FakeCookieJar([CookieFixtures.stored("session")]))
            let expected = CookiesSnapshot(contents: .unread, filter: "")

            let encoded = try JSONEncoder().encode(sut.snapshot)
            let actual = try JSONDecoder().decode(CookiesSnapshot.self, from: encoded)

            #expect(actual == expected)
            #expect(actual.allCookies.isEmpty)
            #expect(actual.count == CookieCount(shown: 0, total: 0))
        }

        @Test("Every command, encoded to JSON and decoded, drives the stores through a direct transport")
        func commandsRoundTrip() async throws {
            let jar = FakeCookieJar([
                CookieFixtures.stored("session", domain: "api.example.com"),
                CookieFixtures.stored("csrf", domain: "web.example.com", in: .webView),
                CookieFixtures.stored("theme", domain: "web.example.com", in: .webView)
            ])
            let sut = DebugDrawerPluginTransport.direct(to: CookiesModel(jar: jar))
            let snapshots = sut.snapshots()
            let readAndDelete = [
                CookiesCommand(.reload),
                CookiesCommand(.delete(StoredCookie.ID(store: .urlSession, name: "session", domain: "api.example.com", path: "/")))
            ]
            // Delete All deletes what is shown as it is sent, so it waits for the read.
            let filterAndDeleteShown = [CookiesCommand(.setFilter("csrf")), CookiesCommand(.deleteShown)]
            let expectedDeleted = [
                StoredCookie.ID(store: .urlSession, name: "session", domain: "api.example.com", path: "/"),
                StoredCookie.ID(store: .webView, name: "csrf", domain: "web.example.com", path: "/")
            ]
            let expectedLeft = [StoredCookie.ID(store: .webView, name: "theme", domain: "web.example.com", path: "/")]

            for command in readAndDelete {
                try sut.send(JSONDecoder().decode(CookiesCommand.self, from: JSONEncoder().encode(command)))
            }
            for await snapshot in snapshots where snapshot.allCookies.count == 2 {
                break
            }
            for command in filterAndDeleteShown {
                try sut.send(JSONDecoder().decode(CookiesCommand.self, from: JSONEncoder().encode(command)))
            }
            for await snapshot in snapshots where snapshot.allCookies.map(\.id) == expectedLeft {
                break
            }

            #expect(jar.deleted == expectedDeleted)
            #expect(sut.snapshot.filter == "csrf")
            #expect(sut.snapshot.allCookies.map(\.id) == expectedLeft)
        }

        @Test("Refresh lists both stores' cookies, by domain, then name, then path, each with its store")
        func refreshListsBothStores() async {
            let jar = FakeCookieJar([
                CookieFixtures.stored("theme", domain: "web.example.com", in: .webView),
                CookieFixtures.stored("session", domain: "api.example.com"),
                CookieFixtures.stored("csrf", domain: "web.example.com", in: .webView)
            ])
            let sut = DebugDrawerPluginTransport.direct(to: CookiesModel(jar: jar))
            let snapshots = sut.snapshots()
            let expected = [
                StoredCookie.ID(store: .urlSession, name: "session", domain: "api.example.com", path: "/"),
                StoredCookie.ID(store: .webView, name: "csrf", domain: "web.example.com", path: "/"),
                StoredCookie.ID(store: .webView, name: "theme", domain: "web.example.com", path: "/")
            ]

            sut.send(CookiesCommand(.reload))
            var actual: [StoredCookie.ID] = []
            for await snapshot in snapshots where snapshot.contents != .unread {
                actual = snapshot.allCookies.map(\.id)
                break
            }

            #expect(actual == expected)
        }

        @Test("Refresh reads the stores again, so a cookie set since shows")
        func refreshReadsAgain() async {
            let jar = FakeCookieJar([CookieFixtures.stored("session")])
            let sut = DebugDrawerPluginTransport.direct(to: CookiesModel(jar: jar))
            let snapshots = sut.snapshots()
            sut.send(CookiesCommand(.reload))
            for await snapshot in snapshots where snapshot.allCookies.count == 1 {
                break
            }
            jar.set(CookieFixtures.stored("theme"))
            let expectedNames = ["session", "theme"]

            sut.send(CookiesCommand(.reload))
            var actual: [String] = []
            for await snapshot in snapshots where snapshot.allCookies.count == 2 {
                actual = snapshot.allCookies.map(\.name)
                break
            }

            #expect(actual == expectedNames)
        }

        @Test("A row is identified by its store, name, domain and path, so the same cookie in both stores is two rows")
        func identityIncludesStore() async {
            let jar = FakeCookieJar([
                CookieFixtures.stored("session", in: .urlSession),
                CookieFixtures.stored("session", in: .webView),
                CookieFixtures.stored("session", path: "/admin", in: .urlSession),
                CookieFixtures.stored("session", domain: "other.example.com", in: .urlSession)
            ])
            let sut = DebugDrawerPluginTransport.direct(to: CookiesModel(jar: jar))
            let snapshots = sut.snapshots()
            let expectedCount = 4

            sut.send(CookiesCommand(.reload))
            var actual: Set<StoredCookie.ID> = []
            for await snapshot in snapshots where snapshot.contents != .unread {
                actual = Set(snapshot.allCookies.map(\.id))
                break
            }

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
            let sut = DebugDrawerPluginTransport.direct(to: CookiesModel(jar: jar))
            let snapshots = sut.snapshots()
            sut.send(CookiesCommand(.reload))
            let expectedDeleted = [webView.id]
            let expectedLeft = [StoredCookie.ID(store: .urlSession, name: "session", domain: "example.com", path: "/")]

            sut.send(CookiesCommand(.delete(webView.id)))
            var actual: [StoredCookie.ID] = []
            for await snapshot in snapshots where snapshot.allCookies.count == 1 {
                actual = snapshot.allCookies.map(\.id)
                break
            }

            #expect(jar.deleted == expectedDeleted)
            #expect(actual == expectedLeft)
        }

        @Test("Delete All deletes only the cookies the filter shows, each from its own store")
        func deleteShownOnly() async {
            let jar = FakeCookieJar([
                CookieFixtures.stored("session", domain: "api.example.com"),
                CookieFixtures.stored("session", domain: "web.example.com", in: .webView),
                CookieFixtures.stored("theme", domain: "web.example.com", in: .webView)
            ])
            let sut = DebugDrawerPluginTransport.direct(to: CookiesModel(jar: jar))
            let snapshots = sut.snapshots()
            sut.send(CookiesCommand(.reload))
            for await snapshot in snapshots where snapshot.allCookies.count == 3 {
                break
            }
            sut.send(CookiesCommand(.setFilter("SESSION")))
            let expectedDeleted = [
                StoredCookie.ID(store: .urlSession, name: "session", domain: "api.example.com", path: "/"),
                StoredCookie.ID(store: .webView, name: "session", domain: "web.example.com", path: "/")
            ]
            let expectedLeft = [StoredCookie.ID(store: .webView, name: "theme", domain: "web.example.com", path: "/")]

            sut.send(CookiesCommand(.deleteShown))
            var actual: [StoredCookie.ID] = []
            for await snapshot in snapshots where snapshot.allCookies.count == 1 {
                actual = snapshot.allCookies.map(\.id)
                break
            }

            #expect(jar.deleted == expectedDeleted)
            #expect(actual == expectedLeft)
        }

        @Test("Delete All deletes the cookies shown when it is sent, even if the filter changes before the deletes run")
        func deleteShownAsSent() async {
            let jar = FakeCookieJar([
                CookieFixtures.stored("session", domain: "api.example.com"),
                CookieFixtures.stored("theme", domain: "web.example.com", in: .webView)
            ])
            let sut = DebugDrawerPluginTransport.direct(to: CookiesModel(jar: jar))
            let snapshots = sut.snapshots()
            sut.send(CookiesCommand(.reload))
            for await snapshot in snapshots where snapshot.allCookies.count == 2 {
                break
            }
            sut.send(CookiesCommand(.setFilter("session")))
            let expectedDeleted = [StoredCookie.ID(store: .urlSession, name: "session", domain: "api.example.com", path: "/")]

            sut.send(CookiesCommand(.deleteShown))
            sut.send(CookiesCommand(.setFilter("")))
            for await snapshot in snapshots where snapshot.allCookies.count == 1 {
                break
            }

            #expect(jar.deleted == expectedDeleted)
            #expect(sut.snapshot.allCookies.map(\.name) == ["theme"])
        }

        @Test("With no filter, Delete All deletes every cookie in both stores")
        func deleteAllUnfiltered() async {
            let jar = FakeCookieJar([
                CookieFixtures.stored("session", domain: "api.example.com"),
                CookieFixtures.stored("theme", domain: "web.example.com", in: .webView)
            ])
            let sut = DebugDrawerPluginTransport.direct(to: CookiesModel(jar: jar))
            let snapshots = sut.snapshots()
            sut.send(CookiesCommand(.reload))
            for await snapshot in snapshots where snapshot.allCookies.count == 2 {
                break
            }
            let expectedDeletes = 2

            sut.send(CookiesCommand(.deleteShown))
            for await snapshot in snapshots where snapshot.allCookies.isEmpty {
                break
            }

            #expect(jar.deleted.count == expectedDeletes)
            #expect(sut.snapshot.contents == .cookies([]))
        }

        @Test("A filter that matches nothing makes Delete All delete nothing, and the stores are read again")
        func deleteShownNoMatches() async {
            let jar = FakeCookieJar([CookieFixtures.stored("session")])
            let sut = DebugDrawerPluginTransport.direct(to: CookiesModel(jar: jar))
            let snapshots = sut.snapshots()
            var changes = snapshots.makeAsyncIterator()
            sut.send(CookiesCommand(.reload))
            var current = await changes.next()
            while current?.contents == .unread {
                current = await changes.next()
            }
            sut.send(CookiesCommand(.setFilter("nothing-matches")))
            _ = await changes.next()

            // Delete All changes the snapshot once, as it reads the stores again after deleting.
            sut.send(CookiesCommand(.deleteShown))
            let actual = await changes.next()

            #expect(jar.deleted.isEmpty)
            #expect(actual?.allCookies.count == 1)
            #expect(actual?.shownCookies.isEmpty == true)
        }

        @Test("A delete sent right after a refresh lands after it, so the refresh's older list doesn't bring the cookie back")
        func commandsRunInOrder() async {
            let session = CookieFixtures.stored("session")
            let jar = FakeCookieJar([session, CookieFixtures.stored("theme")])
            let sut = DebugDrawerPluginTransport.direct(to: CookiesModel(jar: jar))
            let snapshots = sut.snapshots()
            let expectedCalls: [FakeCookieJar.Call] = [.read, .delete(session.id), .read, .read]
            let expectedNames = ["theme"]

            sut.send(CookiesCommand(.reload))
            sut.send(CookiesCommand(.delete(session.id)))
            sut.send(CookiesCommand(.reload))
            for await _ in snapshots where jar.calls.count == expectedCalls.count {
                break
            }

            #expect(jar.calls == expectedCalls)
            #expect(sut.snapshot.allCookies.map(\.name) == expectedNames)
        }

        @Test("The count is the cookies the filter shows, of every cookie in both stores, and the filter changes at once")
        func countFollowsFilter() async {
            let jar = FakeCookieJar([
                CookieFixtures.stored("session", domain: "api.example.com"),
                CookieFixtures.stored("theme", domain: "web.example.com", in: .webView),
                CookieFixtures.stored("csrf", domain: "web.example.com", in: .webView)
            ])
            let sut = DebugDrawerPluginTransport.direct(to: CookiesModel(jar: jar))
            let snapshots = sut.snapshots()
            sut.send(CookiesCommand(.reload))
            for await snapshot in snapshots where snapshot.allCookies.count == 3 {
                break
            }
            let expectedUnfiltered = CookieCount(shown: 3, total: 3)
            let expectedFiltered = CookieCount(shown: 2, total: 3)

            let unfiltered = sut.snapshot.count
            sut.send(CookiesCommand(.setFilter("web.")))
            let actual = sut.snapshot.count

            #expect(unfiltered == expectedUnfiltered)
            #expect(actual == expectedFiltered)
            #expect(sut.snapshot.shownCookies.map(\.name) == ["csrf", "theme"])
        }

        @Test("Before the stores are read there are no cookies, and the count is zero")
        func unread() {
            let sut = CookiesModel(jar: FakeCookieJar([CookieFixtures.stored("session")]))
            let expected = CookieCount(shown: 0, total: 0)

            let actual = sut.snapshot.count

            #expect(actual == expected)
            #expect(sut.snapshot.allCookies.isEmpty)
        }

        @Test("Installed in two drawers, the cookies read stay until both remove it; then they are dropped and the filter stays")
        func installCounting() async {
            let model = CookiesModel(jar: FakeCookieJar([CookieFixtures.stored("session")]))
            // Both drawers live through the test, so their identifiers can't be reused.
            let firstDrawer = DebugDrawer()
            let secondDrawer = DebugDrawer()
            let first = ObjectIdentifier(firstDrawer)
            let second = ObjectIdentifier(secondDrawer)
            model.install(in: first)
            model.install(in: second)
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = transport.snapshots()
            transport.send(CookiesCommand(.reload))
            transport.send(CookiesCommand(.setFilter("sess")))
            for await snapshot in snapshots where snapshot.allCookies.count == 1 {
                break
            }

            model.uninstall(from: first)
            let afterFirst = model.snapshot.contents
            model.uninstall(from: second)
            let afterSecond = model.snapshot
            withExtendedLifetime((firstDrawer, secondDrawer)) {}

            #expect(afterFirst == .cookies([CookieFixtures.stored("session")]))
            #expect(afterSecond.contents == .unread)
            #expect(afterSecond.filter == "sess")
        }

        @Test("Removing the plugin from a drawer it was never installed in drops nothing")
        func uninstallUnknownDrawer() async {
            let model = CookiesModel(jar: FakeCookieJar([CookieFixtures.stored("session")]))
            let installed = DebugDrawer()
            let other = DebugDrawer()
            model.install(in: ObjectIdentifier(installed))
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = transport.snapshots()
            transport.send(CookiesCommand(.reload))
            for await snapshot in snapshots where snapshot.allCookies.count == 1 {
                break
            }

            model.uninstall(from: ObjectIdentifier(other))
            withExtendedLifetime((installed, other)) {}

            #expect(model.snapshot.allCookies.count == 1)
        }
    }
#endif
