#if DEBUG
    import Combine
    @testable import DebugDrawerAppStateReset
    @testable import DebugDrawerReceiver
    import Foundation
    import Security
    import Testing

    // The model alone, over a fixture container and fakes for the other seams, with real sessions
    // and a foreground the test moves. Each wait is for the snapshot a step should produce, never
    // for time.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppStateResetRequestsTests {
        @Test("`.all` holds every category but the keychain")
        func allLeavesKeychainOut() {
            let expected: Set<AppStateReset.Category> = [.userDefaults, .files, .caches, .cookies, .urlCache, .appCleanup]

            let actual = Set<AppStateReset.Category>.all

            #expect(actual == expected)
            #expect(!actual.contains(.keychain))
        }

        @Test("Allowing `.all` allows no keychain, and the app's cleanup only with one supplied")
        func allowedAll() throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let withCleanup = try ResetFixture(cleanup: AppStateReset.Cleanup("Close the database") {})
            defer { withCleanup.remove() }
            let sessions = DebugDrawerSessions(maximumDuration: 300)

            let sut = AppStateResetRequests(
                sessions: sessions, allowing: .all, allowingKeychain: false, appState: fixture.appState, launchURL: nil,
                foreground: FakeForeground(), now: Date.init
            )
            let cleaning = AppStateResetRequests(
                sessions: sessions, allowing: .all, allowingKeychain: false, appState: withCleanup.appState, launchURL: nil,
                foreground: FakeForeground(), now: Date.init
            )

            #expect(sut.snapshot.allowed == [.userDefaults, .files, .caches, .cookies, .urlCache])
            #expect(cleaning.snapshot.allowed == [.userDefaults, .files, .caches, .cookies, .urlCache, .appCleanup])
        }

        @Test("The keychain is allowed only with allowingKeychain, beside the categories named")
        func keychainOptIn() throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let sessions = DebugDrawerSessions(maximumDuration: 300)

            let sut = AppStateResetRequests(
                sessions: sessions, allowing: [.caches], allowingKeychain: true, appState: fixture.appState, launchURL: nil,
                foreground: FakeForeground(), now: Date.init
            )

            #expect(sut.allowed == [.caches, .keychain])
            #expect(sut.snapshot.allowed == [.keychain, .caches])
        }

        @Test("Outside a session the snapshot holds only the allowed categories, and a refresh reads nothing")
        func nothingOutsideSession() throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let launchURL = URL(string: "shop-internal://reset")
            let sut = AppStateResetRequests(
                sessions: sessions, allowing: [.userDefaults], allowingKeychain: true, appState: fixture.appState, launchURL: launchURL,
                foreground: FakeForeground(), now: Date.init
            )
            let expected = AppStateResetRequests.Snapshot(
                sessionID: nil, allowed: [.userDefaults, .keychain], activity: .idle, listing: nil, lastReset: nil, launchURL: launchURL
            )

            sut.perform(.refresh)

            #expect(sut.snapshot == expected)
            #expect(fixture.keychain.reads == 0)
        }

        @Test("A refresh in a session lists each allowed category by name (keys, paths, domains, keychain services), not accounts or DebugDrawer's")
        func refreshLists() async throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = AppStateResetRequests(
                sessions: sessions, allowing: [.userDefaults, .files, .caches, .cookies], allowingKeychain: true,
                appState: fixture.appState, launchURL: nil, foreground: FakeForeground(), now: Date.init
            )
            sessions.perform(.open(duration: 60))

            sut.perform(.refresh)
            for await snapshot in sut.$snapshot.values where snapshot.listing != nil {
                break
            }

            let listing = try #require(sut.snapshot.listing)
            let items = Dictionary(uniqueKeysWithValues: listing.categories.map { ($0.category, $0.items.map(\.text)) })
            #expect(listing.categories.map(\.category) == [.userDefaults, .keychain, .files, .caches, .cookies])
            #expect(items[.userDefaults] == ["counter", "onboarded"])
            #expect(items[.keychain] == ["api.example.com", "Signing key"])
            #expect(items[.files] == ["Documents/notes.txt", "Application Support/store.sqlite"])
            #expect(items[.caches] == ["Caches/thumbs"])
            #expect(items[.cookies] == ["example.com", "other.org"])
            #expect(listing.categories.first { $0.category == .cookies }?.items.map(\.detail) == ["2 cookies", "1 cookie"])
            let encoded = try JSONEncoder().encode(sut.snapshot)
            for absent in ["alice", "theme", "tracking", "DebugDrawer.LogLevels", "com.debugdrawer", "DebugDrawer Export", "Recordings"] {
                #expect(encoded.range(of: Data(absent.utf8)) == nil, "The snapshot names \(absent)")
            }
            #expect(sut.snapshot.activity == .idle)
        }

        @Test("A reset of a category the host didn't allow is refused notExposed, the keychain included")
        func notAllowedRefused() throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let sut = AppStateResetRequests(
                sessions: DebugDrawerSessions(maximumDuration: 300), allowing: .all, allowingKeychain: false, appState: fixture.appState,
                launchURL: nil, foreground: FakeForeground(), now: Date.init
            )

            let keychain = sut.refusal(of: .reset([AppStateResetRequests.Confirmation(category: .keychain, revision: "r")]))
            let cleanup = sut.refusal(of: .reset([AppStateResetRequests.Confirmation(category: .appCleanup, revision: "r")]))

            #expect(keychain == .notExposed)
            #expect(cleanup == .notExposed)
        }

        @Test("A reset of no category, or of one twice, is malformed")
        func malformedResets() throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let sut = AppStateResetRequests(
                sessions: DebugDrawerSessions(maximumDuration: 300), allowing: .all, allowingKeychain: false, appState: fixture.appState,
                launchURL: nil, foreground: FakeForeground(), now: Date.init
            )
            let twice = [
                AppStateResetRequests.Confirmation(category: .caches, revision: "a"),
                AppStateResetRequests.Confirmation(category: .caches, revision: "a")
            ]

            #expect(sut.refusal(of: .reset([])) == .malformedCommand)
            #expect(sut.refusal(of: .reset(twice)) == .malformedCommand)
            #expect(sut.refusal(of: .refresh) == nil)
            #expect(sut.refusal(of: .cancel) == nil)
        }

        @Test("A reset confirmed before the listing was read, or at another revision, is refused staleConfirmation; at the listing's, it is taken")
        func staleConfirmationRefused() async throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = AppStateResetRequests(
                sessions: sessions, allowing: [.caches], allowingKeychain: false, appState: fixture.appState, launchURL: nil,
                foreground: FakeForeground(), now: Date.init
            )
            sessions.perform(.open(duration: 60))
            let beforeListing = sut.refusal(of: .reset([AppStateResetRequests.Confirmation(category: .caches, revision: "anything")]))

            sut.perform(.refresh)
            for await snapshot in sut.$snapshot.values where snapshot.listing != nil {
                break
            }
            let revision = try #require(sut.snapshot.listing?.categories.first?.revision)

            #expect(beforeListing == .staleConfirmation)
            #expect(sut.refusal(of: .reset([AppStateResetRequests.Confirmation(category: .caches, revision: revision + "0")])) == .staleConfirmation)
            #expect(sut.refusal(of: .reset([AppStateResetRequests.Confirmation(category: .caches, revision: revision)])) == nil)
        }

        @Test("A reset waits while the app is in the background, then clears exactly what was confirmed in the foreground, and reports it")
        func waitsForForeground() async throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let foreground = FakeForeground()
            let requested = Date(timeIntervalSinceReferenceDate: 1000)
            let sut = AppStateResetRequests(
                sessions: sessions, allowing: [.userDefaults, .caches, .files, .cookies, .urlCache], allowingKeychain: false,
                appState: fixture.appState, launchURL: nil, foreground: foreground, now: { requested }
            )
            sessions.perform(.open(duration: 60))
            sut.perform(.refresh)
            for await snapshot in sut.$snapshot.values where snapshot.listing != nil {
                break
            }
            let revisions = Dictionary(uniqueKeysWithValues: try #require(sut.snapshot.listing).categories.map { ($0.category, $0.revision) })
            let confirmations = [AppStateReset.Category.userDefaults, .caches, .cookies].map {
                AppStateResetRequests.Confirmation(category: $0, revision: revisions[$0] ?? "")
            }
            let expectedResults = [
                AppStateResetRequests.CategoryResult(category: .userDefaults, cleared: 2, failures: []),
                AppStateResetRequests.CategoryResult(category: .cookies, cleared: 3, failures: []),
                AppStateResetRequests.CategoryResult(category: .caches, cleared: 1, failures: [])
            ]

            sut.perform(.reset(confirmations))
            let waiting = sut.snapshot.activity
            let leftWhileWaiting = fixture.preferences.domains[ResetFixture.appDomain]
            let cachesWhileWaiting = fixture.exists("Caches/thumbs/1.png")
            foreground.enter()
            for await snapshot in sut.$snapshot.values where snapshot.lastReset != nil {
                break
            }

            let pending = AppStateResetRequests.PendingReset(categories: [.userDefaults, .caches, .cookies], requested: requested)
            #expect(waiting == .waitingForForeground(pending))
            #expect(leftWhileWaiting?.contains("onboarded") == true)
            #expect(cachesWhileWaiting)
            #expect(sut.snapshot.lastReset == AppStateResetRequests.Report(finished: requested, outcome: .applied(expectedResults)))
            let drawerKeys: Set = ["com.debugdrawer.tweaks.greeting", "DebugDrawer.LogLevels.raisedSubsystems"]
            #expect(fixture.preferences.domains[ResetFixture.appDomain] == drawerKeys)
            #expect(!fixture.exists("Caches/thumbs/1.png"))
            #expect(fixture.exists("Caches/DebugDrawer/Recordings/a.mov"))
            #expect(fixture.exists("Documents/notes.txt"))
            #expect(fixture.cookies.stored.isEmpty)
            #expect(fixture.responseCache.removals == 0)
            #expect(sut.snapshot.listing?.categories.first { $0.category == .caches }?.items == [])
            #expect(sut.snapshot.activity == .idle)
        }

        @Test("A reset taken while the app is in the foreground runs at once")
        func runsInForeground() async throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = AppStateResetRequests(
                sessions: sessions, allowing: [.urlCache], allowingKeychain: false, appState: fixture.appState, launchURL: nil,
                foreground: FakeForeground(isInForeground: true), now: Date.init
            )
            sessions.perform(.open(duration: 60))
            sut.perform(.refresh)
            for await snapshot in sut.$snapshot.values where snapshot.listing != nil {
                break
            }
            let revision = try #require(sut.snapshot.listing?.categories.first?.revision)

            sut.perform(.reset([AppStateResetRequests.Confirmation(category: .urlCache, revision: revision)]))
            for await snapshot in sut.$snapshot.values where snapshot.lastReset != nil {
                break
            }

            #expect(fixture.responseCache.removals == 1)
            let expected = AppStateResetRequests.CategoryResult(category: .urlCache, cleared: 1, failures: [])
            #expect(sut.snapshot.lastReset?.outcome == .applied([expected]))
        }

        @Test("When what a confirmed category holds changes before the reset runs, nothing is deleted and the report names the category")
        func changedNotApplied() async throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let foreground = FakeForeground()
            let sut = AppStateResetRequests(
                sessions: sessions, allowing: [.userDefaults, .caches], allowingKeychain: false, appState: fixture.appState, launchURL: nil,
                foreground: foreground, now: Date.init
            )
            sessions.perform(.open(duration: 60))
            sut.perform(.refresh)
            for await snapshot in sut.$snapshot.values where snapshot.listing != nil {
                break
            }
            let revisions = Dictionary(uniqueKeysWithValues: try #require(sut.snapshot.listing).categories.map { ($0.category, $0.revision) })
            sut.perform(.reset([
                AppStateResetRequests.Confirmation(category: .userDefaults, revision: revisions[.userDefaults] ?? ""),
                AppStateResetRequests.Confirmation(category: .caches, revision: revisions[.caches] ?? "")
            ]))

            fixture.preferences.domains[ResetFixture.appDomain]?.insert("written-since")
            foreground.enter()
            for await snapshot in sut.$snapshot.values where snapshot.lastReset != nil {
                break
            }

            #expect(sut.snapshot.lastReset?.outcome == .notApplied(changed: [.userDefaults]))
            #expect(fixture.preferences.removed.isEmpty)
            #expect(fixture.exists("Caches/thumbs/1.png"))
            #expect(sut.snapshot.listing?.categories.first?.items.map(\.text) == ["counter", "onboarded", "written-since"])
        }

        @Test("A size changing leaves a category's revision as it was, so the reset runs")
        func sizesKeepRevision() async throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = AppStateResetRequests(
                sessions: sessions, allowing: [.caches, .urlCache], allowingKeychain: false, appState: fixture.appState, launchURL: nil,
                foreground: FakeForeground(), now: Date.init
            )
            sessions.perform(.open(duration: 60))
            sut.perform(.refresh)
            for await snapshot in sut.$snapshot.values where snapshot.listing != nil {
                break
            }
            let before = try #require(sut.snapshot.listing).categories.map(\.revision)

            try Data(repeating: 1, count: 4000).write(to: fixture.root.appending(path: "Caches/thumbs/1.png"))
            fixture.responseCache.currentDiskUsage = 9_000_000
            sut.perform(.refresh)
            for await snapshot in sut.$snapshot.values where snapshot.activity == .idle {
                break
            }

            #expect(sut.snapshot.listing?.categories.first?.items.map(\.detail) == [ResetPlan.bytes(4000)])
            #expect(sut.snapshot.listing?.categories.map(\.revision) == before)
        }

        @Test("A reset still waiting is dropped as its session ends, and the next session starts with nothing read")
        func droppedWithSession() async throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let foreground = FakeForeground()
            let sut = AppStateResetRequests(
                sessions: sessions, allowing: [.caches], allowingKeychain: false, appState: fixture.appState, launchURL: nil,
                foreground: foreground, now: Date.init
            )
            sessions.perform(.open(duration: 60))
            sut.perform(.refresh)
            for await snapshot in sut.$snapshot.values where snapshot.listing != nil {
                break
            }
            let revision = try #require(sut.snapshot.listing?.categories.first?.revision)
            sut.perform(.reset([AppStateResetRequests.Confirmation(category: .caches, revision: revision)]))

            sessions.perform(.end)
            foreground.enter()
            sessions.perform(.open(duration: 60))
            sut.perform(.refresh)
            for await snapshot in sut.$snapshot.values where snapshot.listing != nil {
                break
            }

            #expect(fixture.exists("Caches/thumbs/1.png"))
            #expect(sut.snapshot.lastReset == nil)
            #expect(sut.snapshot.activity == .idle)
            #expect(sut.snapshot.listing?.categories.first?.items.map(\.text) == ["Caches/thumbs"])
        }

        @Test("Cancel drops a reset still waiting for the foreground")
        func cancelDrops() async throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let foreground = FakeForeground()
            let sut = AppStateResetRequests(
                sessions: sessions, allowing: [.caches], allowingKeychain: false, appState: fixture.appState, launchURL: nil,
                foreground: foreground, now: Date.init
            )
            sessions.perform(.open(duration: 60))
            sut.perform(.refresh)
            for await snapshot in sut.$snapshot.values where snapshot.listing != nil {
                break
            }
            let revision = try #require(sut.snapshot.listing?.categories.first?.revision)
            sut.perform(.reset([AppStateResetRequests.Confirmation(category: .caches, revision: revision)]))

            sut.perform(.cancel)
            foreground.enter()
            sut.perform(.refresh)
            for await snapshot in sut.$snapshot.values where snapshot.activity == .idle && snapshot.listing != nil {
                break
            }

            #expect(fixture.exists("Caches/thumbs/1.png"))
            #expect(sut.snapshot.lastReset == nil)
        }

        @Test("The keychain is listed and cleared by service, and an item it won't delete is reported without its account")
        func keychainReported() async throws {
            let fixture = try ResetFixture()
            defer { fixture.remove() }
            fixture.keychain.refusals[Data("api.example.com/alice@example.com".utf8)] = errSecInteractionNotAllowed
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let sut = AppStateResetRequests(
                sessions: sessions, allowing: [], allowingKeychain: true, appState: fixture.appState, launchURL: nil,
                foreground: FakeForeground(isInForeground: true), now: Date.init
            )
            sessions.perform(.open(duration: 60))
            sut.perform(.refresh)
            for await snapshot in sut.$snapshot.values where snapshot.listing != nil {
                break
            }
            let revision = try #require(sut.snapshot.listing?.categories.first?.revision)
            let expectedFailure = "api.example.com: \(KeychainError(status: errSecInteractionNotAllowed).message)"

            sut.perform(.reset([AppStateResetRequests.Confirmation(category: .keychain, revision: revision)]))
            for await snapshot in sut.$snapshot.values where snapshot.lastReset != nil {
                break
            }

            let expected = AppStateResetRequests.CategoryResult(category: .keychain, cleared: 1, failures: [expectedFailure])
            #expect(sut.snapshot.lastReset?.outcome == .applied([expected]))
            #expect(fixture.keychain.deleted.map(\.listedName) == ["Signing key"])
        }
    }
#endif
