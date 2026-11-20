// The release build. `--config=release` builds and runs only the performance targets, so this is
// where the capability is tested compiled without DEBUG, as a production app's build is: a real
// receiver, commands left in the store as a sidecar's transport leaves them (the transport is a
// debug-build type), a container in a temporary folder and a real UserDefaults suite, and a
// foreground the test moves. In debug the file is empty; AppStateResetSidecarTests covers the same
// through the sidecar's transport.
#if !DEBUG
    import Combine
    import DebugDrawerAppStateReset
    import DebugDrawerReceiver
    import Foundation
    import Testing

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

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ReleaseAppStateResetTests {
        @Test("In release, a confirmed reset left in the store waits for the foreground, then clears the defaults keys and caches it listed")
        func resetInRelease() async throws {
            let root = FileManager.default.temporaryDirectory
                .appending(path: "ReleaseAppStateResetTests-\(UUID().uuidString)", directoryHint: .isDirectory)
            defer { try? FileManager.default.removeItem(at: root) }
            let thumbnail = root.appending(path: "Caches/thumbs/1.png")
            try FileManager.default.createDirectory(at: thumbnail.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("png".utf8).write(to: thumbnail)
            let suite = "ReleaseAppStateResetTests-\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(true, forKey: "onboarded")
            let appState = AppState(
                domains: [suite],
                preferences: _PreferenceStore(appDomain: "com.example.unused"),
                keychain: _Keychain(),
                container: AppContainer(
                    files: [], caches: [FileArea(name: "Caches", directory: root.appending(path: "Caches"))], kept: [],
                    appFolderName: "com.example.app"
                ),
                cookies: _CookieStore(),
                responseCache: URLCache(memoryCapacity: 0, diskCapacity: 0),
                cleanup: nil
            )
            let sessions = DebugDrawerSessions(maximumDuration: 300)
            let foreground = TestForeground()
            let model = AppStateResetRequests(
                sessions: sessions, allowing: [.userDefaults, .caches], allowingKeychain: false, appState: appState, launchURL: nil,
                foreground: foreground, now: Date.init
            )
            let store = root.appending(path: "Store")
            let receiver = DebugDrawerReceiver(directory: store, sessions: sessions)
            receiver.enable(.appStateReset(model))
            try receiver.start()
            defer { receiver.stop() }
            let layout = AppGroupStoreLayout(directory: receiver.appDirectory)
            /// Leaves `command` for `id` in the store, as a sidecar's transport does, named to run in
            /// `order`.
            func leave(_ payload: Data, for id: String, order: Int) throws {
                let document = StoreDocument(TransportMessage(kind: .command, pluginID: id, payload: payload))
                try layout.write(document.encoded(), to: layout.commands.appending(path: "\(order).json"))
            }
            try leave(TransportMessage.payload(DebugDrawerSessionCommand.open(duration: 60)), for: DebugDrawerSessions.pluginID, order: 0)
            try leave(TransportMessage.payload(AppStateResetRequests.Command.refresh), for: AppStateResetRequests.pluginID, order: 1)
            receiver.reevaluateGates()
            for await snapshot in model.$snapshot.values where snapshot.listing != nil {
                break
            }
            let listing = try #require(model.snapshot.listing)
            let confirmations = listing.categories.map { AppStateResetRequests.Confirmation(category: $0.category, revision: $0.revision) }

            try leave(TransportMessage.payload(AppStateResetRequests.Command.reset(confirmations)), for: AppStateResetRequests.pluginID, order: 2)
            receiver.reevaluateGates()
            let waiting: [AppStateReset.Category]? =
                if case let .waitingForForeground(pending) = model.snapshot.activity { pending.categories } else { nil }
            let thumbnailWhileWaiting = FileManager.default.fileExists(atPath: thumbnail.path(percentEncoded: false))
            foreground.enter()
            for await snapshot in model.$snapshot.values where snapshot.lastReset != nil {
                break
            }

            #expect(listing.categories.map(\.items) == [
                [AppStateResetRequests.Item(text: "onboarded", detail: nil)], [AppStateResetRequests.Item(text: "Caches/thumbs", detail: "3 bytes")]
            ])
            #expect(waiting == [.userDefaults, .caches])
            #expect(thumbnailWhileWaiting)
            #expect(model.snapshot.lastReset?.outcome == .applied([
                AppStateResetRequests.CategoryResult(category: .userDefaults, cleared: 1, failures: []),
                AppStateResetRequests.CategoryResult(category: .caches, cleared: 1, failures: [])
            ]))
            #expect(defaults.object(forKey: "onboarded") == nil)
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: "Caches/thumbs").path(percentEncoded: false)))
            #expect(sessions.snapshot.isActive)
        }
    }
#endif
