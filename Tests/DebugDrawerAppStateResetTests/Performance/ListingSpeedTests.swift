// A sidecar's refresh reads every allowed category, and the reset reads them all again before it
// deletes anything, so both must stay quick for an app that has piled up state: thousands of
// defaults keys and cached files, most of them past the 500 a category lists, all of them in its
// revision.
import Combine
import DebugDrawerAppStateReset
import DebugDrawerReceiver
import DebugDrawerTestSupport
import Foundation
import Testing

/// An app that is always in the foreground.
@MainActor
private final class ForegroundApp: AppForeground {
    let isInForeground = true
    let enteredForeground = Empty<Void, Never>().eraseToAnyPublisher()
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ListingSpeedTests {
    @Test("A refresh over 2,000 defaults keys and 2,000 cached files lists and revisions them in under two seconds")
    func largeListing() async throws {
        let root = FileManager.default.temporaryDirectory
            .appending(path: "ListingSpeedTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let caches = root.appending(path: "Caches", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: caches, withIntermediateDirectories: true)
        for index in 0 ..< 2000 {
            try Data("x".utf8).write(to: caches.appending(path: "\(index).png"))
        }
        let suite = temporarySuiteName("ListingSpeedTests")
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for index in 0 ..< 2000 {
            defaults.set(index, forKey: "key\(index)")
        }
        let appState = AppState(
            domains: [suite],
            preferences: _PreferenceStore(appDomain: "com.example.unused"),
            keychain: _Keychain(),
            container: AppContainer(files: [], caches: [FileArea(name: "Caches", directory: caches)], kept: [], appFolderName: "com.example.app"),
            cookies: _CookieStore(),
            responseCache: URLCache(memoryCapacity: 0, diskCapacity: 0),
            cleanup: nil
        )
        let sessions = DebugDrawerSessions(maximumDuration: 300)
        let model = try AppStateResetRequests(
            sessions: sessions, allowing: [.userDefaults, .caches], allowingKeychain: false, appState: appState, launchURL: nil,
            foreground: ForegroundApp(), now: Date.init
        )
        sessions.perform(.open(duration: 60))
        let clock = ContinuousClock()
        let started = clock.now

        model.perform(.refresh)
        for await snapshot in model.$snapshot.values where snapshot.listing != nil {
            break
        }
        let elapsed = clock.now - started

        #expect(model.snapshot.listing?.categories.map(\.unlistedCount) == [1500, 1500])
        #expect(elapsed < .seconds(2), "The refresh took \(elapsed)")
    }
}
