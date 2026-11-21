#if DEBUG && os(macOS)
    import Combine
    import DebugDrawer
    @testable import DebugDrawerAppStateReset
    @testable import DebugDrawerReceiver
    @testable import DebugDrawerSidecarKit
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    /// The app's foreground as the test says: in the background until it enters.
    @MainActor
    private final class TestForeground: AppForeground {
        private(set) var isInForeground = false
        private let entered = PassthroughSubject<Void, Never>()

        var enteredForeground: AnyPublisher<Void, Never> {
            entered.eraseToAnyPublisher()
        }

        func enter() {
            isInForeground = true
            entered.send()
        }
    }

    /// A URL cache that reports nothing and counts its clears.
    @MainActor
    private final class CountingResponseCache: ResponseCache {
        let currentDiskUsage = 0
        let currentMemoryUsage = 0
        private(set) var removals = 0

        func removeAllCachedResponses() {
            removals += 1
        }
    }

    /// No cookies.
    @MainActor
    private struct NoCookies: CookieStore {
        func cookies() async -> [StoredCookie] { [] }
        func delete(_ cookies: [StoredCookie]) async {}
    }

    /// No keychain items.
    @MainActor
    private struct NoKeychain: Keychain {
        func items() throws(KeychainError) -> [KeychainItem] { [] }
        func delete(_ item: KeychainItem) throws(KeychainError) {}
    }

    /// No defaults keys.
    @MainActor
    private struct NoPreferences: PreferenceStore {
        func keys(inDomain name: String) -> [String] { [] }
        func remove(_ keys: [String], fromDomain name: String) {}
    }

    // An app state reset from the production app's receiver to the sidecar's confirmation: the kit
    // lists the app, shows the categories it allows through the plugin over the store, and Reset
    // leaves the confirmed categories for the app, which clears them as it comes to the foreground.
    // Each wait is for the snapshot that step should produce, never for time. Bringing the app
    // forward isn't exercised (it would open an app on the Mac running the tests); without an app
    // in the environment the plugin says to open the app.
    @MainActor
    @Suite(.timeLimit(.minutes(1)), .serialized)
    struct SidecarAppStateResetTests {
        @Test("The kit lists an app serving the reset and, once a session is open, hosts its plugin over the store, which reads that session")
        func hostedOverStore() async throws {
            let root = FileManager.default.temporaryDirectory
                .appending(path: "SidecarAppStateResetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: root) }
            let store = root.appending(path: "Group/DebugDrawer")
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let appState = AppState(
                domains: [], preferences: NoPreferences(), keychain: NoKeychain(),
                container: AppContainer(files: [], caches: [], kept: [], appFolderName: "com.example.shop"),
                cookies: NoCookies(), responseCache: CountingResponseCache(), cleanup: nil
            )
            let model = AppStateResetRequests(
                sessions: sessions, allowing: [.caches, .urlCache], allowingKeychain: false, appState: appState, launchURL: nil,
                foreground: TestForeground(), now: Date.init
            )
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.identity = AppPresence.Identity(bundleIdentifier: "com.example.shop", displayName: "Shop", version: "2.4", build: "881")
            receiver.enable(.appStateReset(model))
            try receiver.start()
            defer { receiver.stop() }
            let listed = try #require(DebugDrawerSidecarAppList(storeDirectory: store).apps.first)
            let sut = try DebugDrawerSidecarConnection(app: listed)
            defer { sut.close() }
            // The receiver serves the capability only within a session.
            sessions.perform(.open(duration: 60))

            let hosted = try await sut.host(.appStateReset)

            #expect(listed.serves(AppStateResetRequests.pluginID))
            #expect(listed.servesInSessionsOnly)
            #expect(throws: (any Error).self) { try hosted.body.inspect().find(text: "Open a session to list what a reset would clear.") }
        }

        @Test("Reset in the confirmation sends the ticked categories at the revisions shown, and the app clears them as it comes to the foreground")
        func resetSendsConfirmation() async throws {
            let root = FileManager.default.temporaryDirectory
                .appending(path: "SidecarAppStateResetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: root) }
            let thumbnail = root.appending(path: "Caches/thumbs/1.png")
            try FileManager.default.createDirectory(at: thumbnail.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("png".utf8).write(to: thumbnail)
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let responseCache = CountingResponseCache()
            let appState = AppState(
                domains: [], preferences: NoPreferences(), keychain: NoKeychain(),
                container: AppContainer(
                    files: [], caches: [FileArea(name: "Caches", directory: root.appending(path: "Caches"))], kept: [],
                    appFolderName: "com.example.shop"
                ),
                cookies: NoCookies(), responseCache: responseCache, cleanup: nil
            )
            let foreground = TestForeground()
            let model = AppStateResetRequests(
                sessions: sessions, allowing: [.caches, .urlCache], allowingKeychain: false, appState: appState, launchURL: nil,
                foreground: foreground, now: Date.init
            )
            sessions.perform(.open(duration: 60))
            model.perform(.refresh)
            for await snapshot in model.$snapshot.values where snapshot.listing != nil {
                break
            }
            let sut = AppStateResetSidecarView(transport: .direct(to: model), selection: [.caches], isConfirming: true)

            try sut.inspect().find(button: "Reset").tap()
            let waiting: [AppStateReset.Category]? =
                if case let .waitingForForeground(pending) = model.snapshot.activity { pending.categories } else { nil }
            let thumbnailWhileWaiting = FileManager.default.fileExists(atPath: thumbnail.path(percentEncoded: false))
            foreground.enter()
            for await snapshot in model.$snapshot.values where snapshot.lastReset != nil {
                break
            }

            #expect(waiting == [.caches])
            #expect(thumbnailWhileWaiting)
            let expected = AppStateResetRequests.CategoryResult(category: .caches, cleared: 1, failures: [])
            #expect(model.snapshot.lastReset?.outcome == .applied([expected]))
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Caches/thumbs").path(percentEncoded: false)))
            #expect(responseCache.removals == 0)
        }

        @Test("A listing's confirmations are the ticked categories, each at the revision it shows")
        func confirmations() {
            let listing = AppStateResetRequests.Listing(read: Date(timeIntervalSinceReferenceDate: 0), categories: [
                AppStateResetRequests.CategoryListing(
                    category: .userDefaults, summary: "2 keys", items: [], unlistedCount: 0, problem: nil, revision: "a1"
                ),
                AppStateResetRequests.CategoryListing(category: .caches, summary: "Empty", items: [], unlistedCount: 0, problem: nil, revision: "b2")
            ])
            let expected = [AppStateResetRequests.Confirmation(category: .caches, revision: "b2")]

            let actual = listing.confirmations(of: [.caches, .keychain])

            #expect(actual == expected)
        }

        @Test("The confirmation lists every item of each category, says how many more it holds, and hands Reset and Cancel")
        func confirmationLists() throws {
            let categories = [
                AppStateResetRequests.CategoryListing(
                    category: .userDefaults, summary: "2 keys",
                    items: [AppStateResetRequests.Item(text: "onboarded", detail: nil), AppStateResetRequests.Item(text: "lastOrder", detail: nil)],
                    unlistedCount: 0, problem: nil, revision: "a1"
                ),
                AppStateResetRequests.CategoryListing(
                    category: .files, summary: "503 items · 1 MB",
                    items: [AppStateResetRequests.Item(text: "Documents/notes.txt", detail: "5 bytes")],
                    unlistedCount: 502, problem: nil, revision: "c3"
                )
            ]
            var resets = 0
            var cancels = 0
            let sut = AppStateResetConfirmationSection(categories: categories, reset: { resets += 1 }, cancel: { cancels += 1 })

            try sut.inspect().find(button: "Reset").tap()
            try sut.inspect().find(button: "Cancel").tap()

            #expect(resets == 1)
            #expect(cancels == 1)
            let listed = [
                "UserDefaults: 2 keys", "onboarded", "lastOrder", "Files: 503 items · 1 MB", "Documents/notes.txt", "5 bytes", "and 502 more"
            ]
            for text in listed {
                #expect(throws: Never.self, "The confirmation doesn't list \(text)") { try sut.inspect().find(text: text) }
            }
        }

        @Test("A checkbox ticks its category, Review stays off with nothing ticked, and Refresh and Review hand their actions")
        func choice() throws {
            let listing = AppStateResetRequests.Listing(read: Date(timeIntervalSinceReferenceDate: 0), categories: [
                AppStateResetRequests.CategoryListing(
                    category: .caches, summary: "1 item · 3 bytes", items: [], unlistedCount: 0, problem: nil, revision: "b2"
                ),
                AppStateResetRequests.CategoryListing(
                    category: .keychain, summary: "Unavailable", items: [], unlistedCount: 0,
                    problem: "A required entitlement isn't present. (-34018)", revision: "k"
                )
            ])
            var selection: Set<AppStateReset.Category> = []
            var refreshes = 0
            var reviews = 0
            let binding = Binding(get: { selection }, set: { selection = $0 })
            let empty = AppStateResetChoiceSection(listing: listing, selection: binding, refresh: { refreshes += 1 }, review: { reviews += 1 })
            let reviewWhileEmpty = try empty.inspect().find(button: "Review Reset…").isDisabled()

            try empty.inspect().find(ViewType.Toggle.self, where: { try $0.accessibilityLabel().string() == "Clear Caches" }).tap()
            let ticked = AppStateResetChoiceSection(listing: listing, selection: binding, refresh: { refreshes += 1 }, review: { reviews += 1 })
            try ticked.inspect().find(button: "Review Reset…").tap()
            try ticked.inspect().find(button: "Refresh").tap()

            #expect(reviewWhileEmpty)
            #expect(selection == [.caches])
            #expect(reviews == 1)
            #expect(refreshes == 1)
            #expect(throws: Never.self) { try ticked.inspect().find(text: "A required entitlement isn't present. (-34018)") }
        }

        @Test("A reset waiting for the foreground is named with its categories and hands Cancel")
        func waitingRow() throws {
            let pending = AppStateResetRequests.PendingReset(categories: [.caches, .cookies], requested: Date(timeIntervalSinceReferenceDate: 0))
            var cancels = 0
            let sut = AppStateResetActivityRow(activity: .waitingForForeground(pending)) { cancels += 1 }

            try sut.inspect().find(button: "Cancel Reset").tap()

            #expect(cancels == 1)
            #expect(throws: Never.self) { try sut.inspect().find(text: "The app clears these as it next comes to the foreground.") }
        }

        @Test("The last reset reads as each category's count and failures, or as nothing deleted when the listing changed")
        func report() throws {
            let applied = AppStateResetRequestsReport.applied
            let notApplied = AppStateResetRequests.Report(finished: Date(timeIntervalSinceReferenceDate: 0), outcome: .notApplied(changed: [.files]))

            let appliedView = AppStateResetReportSection(report: applied)
            let notAppliedView = AppStateResetReportSection(report: notApplied)

            #expect(throws: Never.self) { try appliedView.inspect().find(text: "Documents/locked.txt: Permission denied") }
            let notAppliedText = "What these held changed after you confirmed, so nothing was deleted. Review the list and reset again."
            #expect(throws: Never.self) { try notAppliedView.inspect().find(text: notAppliedText) }
        }

        @Test("Without a session, or with no category allowed, the plugin says so")
        func emptyStates() throws {
            let appState = AppState(
                domains: [], preferences: NoPreferences(), keychain: NoKeychain(),
                container: AppContainer(files: [], caches: [], kept: [], appFolderName: "com.example.shop"),
                cookies: NoCookies(), responseCache: CountingResponseCache(), cleanup: nil
            )
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let allowing = AppStateResetRequests(
                sessions: sessions, allowing: [.caches], allowingKeychain: false, appState: appState, launchURL: nil,
                foreground: TestForeground(), now: Date.init
            )
            let none = AppStateResetRequests(
                sessions: sessions, allowing: [], allowingKeychain: false, appState: appState, launchURL: nil,
                foreground: TestForeground(), now: Date.init
            )

            let noSession = AppStateResetSidecarPlugin(transport: .direct(to: allowing))
            let noCategories = AppStateResetSidecarPlugin(transport: .direct(to: none))

            #expect(throws: Never.self) { try noSession.body.inspect().find(text: "No Session") }
            #expect(throws: Never.self) { try noCategories.body.inspect().find(text: "No Categories Allowed") }
        }

        @Test("The shipped Reset App State plugin is served under the capability's ID")
        func shippedPlugin() {
            let sut = DebugDrawerSidecarPlugin.appStateReset

            #expect([sut.id, sut.title, sut.icon] == [AppStateResetRequests.pluginID, "Reset App State", "arrow.counterclockwise.circle"])
        }
    }

    /// A report fixture: a reset that cleared the caches and left a file it couldn't delete.
    private enum AppStateResetRequestsReport {
        static let applied = AppStateResetRequests.Report(finished: Date(timeIntervalSinceReferenceDate: 0), outcome: .applied([
            AppStateResetRequests.CategoryResult(category: .caches, cleared: 4, failures: []),
            AppStateResetRequests.CategoryResult(category: .files, cleared: 1, failures: ["Documents/locked.txt: Permission denied"])
        ]))
    }
#endif
