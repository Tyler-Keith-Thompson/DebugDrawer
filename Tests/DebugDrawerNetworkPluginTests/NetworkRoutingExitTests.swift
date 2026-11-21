// Installing registers the URL protocol and swizzles every session configuration in the process
// that runs it, so this runs in a child process, in a file of its own, as exit tests need one.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import Foundation
    import Testing

    @Suite("Network capture goes to the drawer that installed the plugin last, in a child process", .timeLimit(.minutes(1)))
    struct NetworkRoutingExitTests {
        @Test("""
        Installed on a drawer of its own, the plugin's store logs the app's requests and its mock rules answer them, the shared store \
        none; once removed, the shared drawer's plugin captures again
        """)
        func latestInstallGetsTheRequests() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                /// Sends a request to a host that never resolves, unless a mock answers it, and
                /// returns its status once it ends; `nil` when it failed.
                func status(of address: String) async throws -> Int? {
                    let url = try #require(URL(string: address))
                    let response = try? await URLSession.shared.data(from: url).1
                    return (response as? HTTPURLResponse)?.statusCode
                }

                @MainActor
                func waitUntilLogged(_ address: String, in store: NetworkStore) async {
                    for await entries in store.$entries.values where entries.contains(where: { $0.url == address && $0.isComplete }) {
                        break
                    }
                }

                @MainActor
                func route() async throws {
                    let suite = "NetworkRoutingExitTests.\(UUID().uuidString)"
                    let defaults = try #require(UserDefaults(suiteName: suite))
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let store = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
                    let mocks = NetworkMocksModel(storage: FakeNetworkMockStorage(), active: NetworkMockRules())
                    let model = NetworkModel(
                        store: store,
                        mocks: mocks,
                        conditions: NetworkConditionsModel(
                            storage: FakeNetworkConditionStorage(), active: NetworkConditions(),
                            scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
                        ),
                        replays: NetworkReplayModel(sender: FakeNetworkReplaySender()),
                        sessions: NetworkSessionsModel()
                    )
                    mocks.load(adding: [NetworkMockRule(
                        name: "Own rule", matcher: .init(host: .exact("own-mock.invalid")), response: .init(status: 201)
                    )])
                    let plugin = NetworkPlugin(model: model)
                    let drawer = DebugDrawer(defaults: defaults)
                    // The app's drawer holds the plugin first, as an app installs it at launch. Its
                    // plugin is registered as installNetwork() registers it, with no session
                    // recorder: one that keeps no sessions deletes the other children's.
                    DebugDrawer.shared.registerGlobal(NetworkPlugin())
                    let ownRequest = "https://own.invalid/\(UUID().uuidString)"
                    let ownMocked = "https://own-mock.invalid/\(UUID().uuidString)"
                    let sharedMocked = "https://own-mock.invalid/\(UUID().uuidString)"
                    let sharedRequest = "https://shared-again.invalid/\(UUID().uuidString)"

                    drawer.registerGlobal(plugin)
                    _ = try await status(of: ownRequest)
                    let mockedStatus = try await status(of: ownMocked)
                    await waitUntilLogged(ownRequest, in: store)
                    await waitUntilLogged(ownMocked, in: store)
                    let ownLogged = Set(store.entries.map(\.url))
                    let sharedWhileInstalled = NetworkStore.shared.entries.map(\.url)
                    drawer.unregisterGlobal(id: plugin.id)
                    let statusAfterRemoval = try await status(of: sharedMocked)
                    _ = try await status(of: sharedRequest)
                    await waitUntilLogged(sharedMocked, in: NetworkStore.shared)
                    await waitUntilLogged(sharedRequest, in: NetworkStore.shared)
                    let sharedLogged = Set(NetworkStore.shared.entries.map(\.url))

                    #expect(ownLogged == [ownRequest, ownMocked])
                    #expect(mockedStatus == 201)
                    #expect(sharedWhileInstalled.isEmpty)
                    #expect(store.entries.isEmpty)
                    #expect(statusAfterRemoval == nil)
                    #expect(sharedLogged == [sharedMocked, sharedRequest])
                }
                try await route()
            }
        }

        @Test("""
        Two drawers of their own: the later one's store logs the requests, and the earlier one's again once the later removes the \
        plugin; the last removal stops capturing
        """)
        func twoDrawersOfTheirOwn() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                @MainActor
                func model() -> NetworkModel {
                    NetworkModel(
                        store: NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage()),
                        mocks: NetworkMocksModel(storage: FakeNetworkMockStorage(), active: NetworkMockRules()),
                        conditions: NetworkConditionsModel(
                            storage: FakeNetworkConditionStorage(), active: NetworkConditions(),
                            scheduler: ManualNetworkConditionScheduler(), random: FixedNetworkConditionRandomSource(0)
                        ),
                        replays: NetworkReplayModel(sender: FakeNetworkReplaySender()),
                        sessions: NetworkSessionsModel()
                    )
                }

                func send(to address: String) async throws {
                    let url = try #require(URL(string: address))
                    _ = try? await URLSession.shared.data(from: url)
                }

                @MainActor
                func waitUntilLogged(_ address: String, in store: NetworkStore) async {
                    for await entries in store.$entries.values where entries.contains(where: { $0.url == address && $0.isComplete }) {
                        break
                    }
                }

                @MainActor
                func route() async throws {
                    let suite = "NetworkRoutingExitTests.\(UUID().uuidString)"
                    let defaults = try #require(UserDefaults(suiteName: suite))
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let firstModel = model()
                    let secondModel = model()
                    let first = DebugDrawer(defaults: defaults)
                    let second = DebugDrawer(defaults: defaults)
                    let toSecond = "https://second.invalid/\(UUID().uuidString)"
                    let toFirst = "https://first.invalid/\(UUID().uuidString)"

                    first.registerGlobal(NetworkPlugin(model: firstModel))
                    second.registerGlobal(NetworkPlugin(model: secondModel))
                    try await send(to: toSecond)
                    await waitUntilLogged(toSecond, in: secondModel.store)
                    let firstWhileSecond = firstModel.store.entries.map(\.url)
                    second.unregisterGlobal(id: NetworkPlugin().id)
                    try await send(to: toFirst)
                    await waitUntilLogged(toFirst, in: firstModel.store)
                    let isCapturingWithOneLeft = !NetworkInterception.isUninstalled
                    first.unregisterGlobal(id: NetworkPlugin().id)

                    #expect(firstWhileSecond.isEmpty)
                    #expect(secondModel.store.entries.isEmpty)
                    #expect(isCapturingWithOneLeft)
                    #expect(NetworkInterception.isUninstalled)
                    #expect(firstModel.store.entries.isEmpty)
                    #expect(NetworkStore.shared.entries.isEmpty)
                }
                try await route()
            }
        }
    }
#endif
