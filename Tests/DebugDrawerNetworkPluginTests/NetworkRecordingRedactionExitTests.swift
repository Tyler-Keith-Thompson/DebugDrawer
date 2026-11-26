// Installing registers the URL protocol and swizzles every session configuration in the process
// that runs it, so this runs in a child process, in a file of its own, as exit tests need one.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @Suite("Network writes its session masked by the rules of the drawer that installed it, in a child process", .timeLimit(.minutes(1)))
    struct NetworkRecordingRedactionExitTests {
        @Test("A request captured for a plugin installed in a drawer of its own is written to the session masked by that drawer's rules")
        func ownDrawerRules() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                /// Sends a GET to `address` with `headers`, which a mock rule answers.
                func send(to address: String, headers: [String: String]) async throws {
                    var request = try URLRequest(url: #require(URL(string: address)))
                    for (name, value) in headers {
                        request.setValue(value, forHTTPHeaderField: name)
                    }
                    _ = try? await URLSession.shared.data(for: request)
                }

                @MainActor
                func waitUntilLogged(_ address: String, in store: NetworkStore) async {
                    for await entries in store.$entries.values where entries.contains(where: { $0.url == address && $0.isComplete }) {
                        break
                    }
                }

                /// The headers of each request the session in `directory` holds, by URL, once
                /// `recorder` has written everything recorded before the call.
                func written(by recorder: NetworkSessionRecorder, in directory: URL) async throws -> [String: [String: String]] {
                    _ = await recorder.previousSessions()
                    let reader = NetworkSessionRecorder(try NetworkSessionPersistence(storage: _NetworkSessionStorage(directory: directory)))
                    let session = try #require(await reader.previousSessions().first { $0.id == recorder.currentName })
                    let log = try await reader.log(of: session)
                    return Dictionary(uniqueKeysWithValues: log.entries.map { ($0.url, $0.requestHeaders) })
                }

                @MainActor
                func record() async throws {
                    let suite = temporarySuiteName("NetworkRecordingRedactionExitTests")
                    let defaults = try #require(UserDefaults(suiteName: suite))
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let directory = URL(filePath: home, directoryHint: .isDirectory).appending(path: "Sessions", directoryHint: .isDirectory)
                    let recorder = NetworkSessionRecorder(try NetworkSessionPersistence(storage: _NetworkSessionStorage(directory: directory)))
                    let store = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
                    store.persist(to: recorder)
                    let mocks = NetworkMocksModel(storage: FakeNetworkMockStorage(), active: NetworkMockRules())
                    mocks.load(adding: [NetworkMockRule(
                        name: "Answer", matcher: .init(host: .exact("recorded.invalid")), response: .init(status: 200)
                    )])
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
                    let plugin = NetworkPlugin(model: model)
                    // The shared drawer masks a header the drawer of the test's own doesn't, and
                    // the other way round; this child's shared drawer is its own to change.
                    DebugDrawer.shared.redaction = DebugDrawerRedaction.none.adding(headers: ["X-Shared-Secret"])
                    let drawer = DebugDrawer(defaults: defaults)
                    drawer.redaction = DebugDrawerRedaction.none.adding(headers: ["X-Own-Secret"])
                    let address = "https://recorded.invalid/\(UUID().uuidString)"
                    let headers = ["X-Own-Secret": "own-only", "X-Shared-Secret": "shared-only"]
                    let expected: [String: String] = ["X-Own-Secret": DebugDrawerRedaction.mask, "X-Shared-Secret": "shared-only"]

                    drawer.registerGlobal(plugin)
                    try await send(to: address, headers: headers)
                    await waitUntilLogged(address, in: store)
                    let actual = try await written(by: recorder, in: directory)[address]
                    drawer.unregisterGlobal(id: plugin.id)

                    #expect(actual?.filter { headers.keys.contains($0.key) } == expected)
                }
                try await record()
            }
        }

        @Test("""
        One plugin installed in two drawers writes its session by the rules of the drawer that installed it last, and by the \
        earlier drawer's once the later removes it
        """)
        func latestInstallRules() async {
            // The children get a home folder of their own, so the files they keep in Application Support and
            // Caches stay out of the Mac's, whatever runs the test; each checks the move took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                /// Sends a GET to `address` with `headers`, which a mock rule answers.
                func send(to address: String, headers: [String: String]) async throws {
                    var request = try URLRequest(url: #require(URL(string: address)))
                    for (name, value) in headers {
                        request.setValue(value, forHTTPHeaderField: name)
                    }
                    _ = try? await URLSession.shared.data(for: request)
                }

                @MainActor
                func waitUntilLogged(_ address: String, in store: NetworkStore) async {
                    for await entries in store.$entries.values where entries.contains(where: { $0.url == address && $0.isComplete }) {
                        break
                    }
                }

                /// The headers of each request the session in `directory` holds, by URL, once
                /// `recorder` has written everything recorded before the call.
                func written(by recorder: NetworkSessionRecorder, in directory: URL) async throws -> [String: [String: String]] {
                    _ = await recorder.previousSessions()
                    let reader = NetworkSessionRecorder(try NetworkSessionPersistence(storage: _NetworkSessionStorage(directory: directory)))
                    let session = try #require(await reader.previousSessions().first { $0.id == recorder.currentName })
                    let log = try await reader.log(of: session)
                    return Dictionary(uniqueKeysWithValues: log.entries.map { ($0.url, $0.requestHeaders) })
                }

                @MainActor
                func record() async throws {
                    let firstSuite = temporarySuiteName("NetworkRecordingRedactionExitTests.first")
                    let secondSuite = temporarySuiteName("NetworkRecordingRedactionExitTests.second")
                    let firstDefaults = try #require(UserDefaults(suiteName: firstSuite))
                    let secondDefaults = try #require(UserDefaults(suiteName: secondSuite))
                    defer {
                        firstDefaults.removePersistentDomain(forName: firstSuite)
                        secondDefaults.removePersistentDomain(forName: secondSuite)
                    }
                    let directory = URL(filePath: home, directoryHint: .isDirectory).appending(path: "Sessions", directoryHint: .isDirectory)
                    let recorder = NetworkSessionRecorder(try NetworkSessionPersistence(storage: _NetworkSessionStorage(directory: directory)))
                    let store = NetworkStore(ignoreStorage: FakeNetworkIgnoreListStorage())
                    store.persist(to: recorder)
                    let mocks = NetworkMocksModel(storage: FakeNetworkMockStorage(), active: NetworkMockRules())
                    mocks.load(adding: [NetworkMockRule(
                        name: "Answer", matcher: .init(host: .exact("recorded.invalid")), response: .init(status: 200)
                    )])
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
                    let plugin = NetworkPlugin(model: model)
                    let first = DebugDrawer(defaults: firstDefaults)
                    first.redaction = DebugDrawerRedaction.none.adding(headers: ["X-First-Secret"])
                    let second = DebugDrawer(defaults: secondDefaults)
                    second.redaction = DebugDrawerRedaction.none.adding(headers: ["X-Second-Secret"])
                    let whileBoth = "https://recorded.invalid/\(UUID().uuidString)"
                    let afterRemoval = "https://recorded.invalid/\(UUID().uuidString)"
                    let headers = ["X-First-Secret": "first-only", "X-Second-Secret": "second-only"]
                    let expectedWhileBoth: [String: String] = ["X-First-Secret": "first-only", "X-Second-Secret": DebugDrawerRedaction.mask]
                    let expectedAfterRemoval: [String: String] = ["X-First-Secret": DebugDrawerRedaction.mask, "X-Second-Secret": "second-only"]

                    first.registerGlobal(plugin)
                    second.registerGlobal(plugin)
                    try await send(to: whileBoth, headers: headers)
                    await waitUntilLogged(whileBoth, in: store)
                    second.unregisterGlobal(id: plugin.id)
                    try await send(to: afterRemoval, headers: headers)
                    await waitUntilLogged(afterRemoval, in: store)
                    let actual = try await written(by: recorder, in: directory)
                    first.unregisterGlobal(id: plugin.id)

                    #expect(actual[whileBoth]?.filter { headers.keys.contains($0.key) } == expectedWhileBoth)
                    #expect(actual[afterRemoval]?.filter { headers.keys.contains($0.key) } == expectedAfterRemoval)
                }
                try await record()
            }
        }
    }
#endif
