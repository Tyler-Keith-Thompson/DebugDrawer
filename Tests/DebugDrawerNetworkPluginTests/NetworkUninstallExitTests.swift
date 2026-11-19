// Installing registers the URL protocol and swizzles every session configuration in the process
// that runs it, and uninstalling puts them back, so this runs in a child process, in a file of its
// own, as exit tests need one.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerNetworkPlugin
    import DebugDrawerTestSupport
    import Foundation
    import ObjectiveC
    import Testing

    /// A getter other code swaps in on top of the plugin's, which calls whatever it replaced.
    extension URLSessionConfiguration {
        @objc fileprivate var onTopProtocolClasses: [AnyClass]? {
            self.onTopProtocolClasses
        }
    }

    @Suite("Uninstalling the Network plugin, in a child process", .timeLimit(.minutes(1)))
    struct NetworkUninstallExitTests {
        @Test("Removing the plugin gives every replaced method its original implementation back, unregisters the URL protocol and forgets the log")
        func uninstallRestoresOriginals() async {
            await #expect(processExitsWith: .success) {
                useHomeFolderOfItsOwn()
                @MainActor
                func implementations() throws -> [IMP] {
                    // The class the session's WebSocket tasks are, which the plugin replaces on.
                    let probe = try URLSession(configuration: .ephemeral).webSocketTask(with: #require(URL(string: "ws://127.0.0.1")))
                    let taskClass: AnyClass = type(of: probe)
                    let methods = try [
                        #require(class_getInstanceMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.protocolClasses))),
                        #require(class_getClassMethod(URLSession.self, NSSelectorFromString("sessionWithConfiguration:delegate:delegateQueue:"))),
                        #require(class_getInstanceMethod(URLSession.self, NSSelectorFromString("webSocketTaskWithURL:"))),
                        #require(class_getInstanceMethod(URLSession.self, NSSelectorFromString("webSocketTaskWithRequest:"))),
                        #require(class_getInstanceMethod(taskClass, NSSelectorFromString("sendMessage:completionHandler:"))),
                        #require(class_getInstanceMethod(taskClass, NSSelectorFromString("receiveMessageWithCompletionHandler:"))),
                        #require(class_getInstanceMethod(taskClass, #selector(URLSessionWebSocketTask.cancel(with:reason:))))
                    ]
                    return methods.map(method_getImplementation)
                }

                /// Sends a request to a host that never resolves, so it fails at once, and returns
                /// once it has.
                func send(to host: String, on session: URLSession) async throws {
                    let url = try #require(URL(string: "https://\(host).invalid/"))
                    _ = try? await session.data(from: url)
                }

                @MainActor
                func waitUntilLogged(_ host: String) async {
                    for await entries in NetworkStore.shared.$entries.values
                        where entries.contains(where: { $0.host == "\(host).invalid" && $0.isComplete }) {
                        break
                    }
                }

                @MainActor
                func uninstallThenReinstall() async throws {
                    let suite = "NetworkUninstallExitTests.\(UUID().uuidString)"
                    let defaults = try #require(UserDefaults(suiteName: suite))
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let drawer = DebugDrawer(defaults: defaults)
                    let expected = try implementations()

                    drawer.installNetwork(sessions: .off)
                    let whileInstalled = try implementations()
                    let configurationListsItWhileInstalled = URLSessionConfiguration.default.protocolClasses?
                        .contains { $0 == DebugNetworkProtocol.self } ?? false
                    // Made while installed, so its configuration keeps the protocol.
                    let madeWhileInstalled = URLSession(configuration: .default)
                    try await send(to: "before-uninstall", on: .shared)
                    await waitUntilLogged("before-uninstall")
                    drawer.unregisterGlobal(id: NetworkPlugin().id)
                    let actual = try implementations()
                    let configurationListsItAfter = URLSessionConfiguration.default.protocolClasses?
                        .contains { $0 == DebugNetworkProtocol.self } ?? false
                    let logAfterUninstall = NetworkStore.shared.entries.count
                    let request = try URLRequest(url: #require(URL(string: "https://shared-after.invalid/")))
                    let protocolTakesRequests = DebugNetworkProtocol.canInit(with: request)
                    try await send(to: "shared-after", on: .shared)
                    try await send(to: "kept-session-after", on: madeWhileInstalled)
                    drawer.unregisterGlobal(id: NetworkPlugin().id)
                    let afterSecondUninstall = try implementations()

                    drawer.installNetwork(sessions: .off)
                    try await send(to: "reinstalled", on: .shared)
                    await waitUntilLogged("reinstalled")
                    let loggedAfterReinstall = Set(NetworkStore.shared.entries.map(\.host))
                    let reinstalled = try implementations()
                    drawer.unregisterGlobal(id: NetworkPlugin().id)
                    let afterLastUninstall = try implementations()

                    #expect(configurationListsItWhileInstalled)
                    #expect(zip(whileInstalled, expected).allSatisfy { $0 != $1 })
                    #expect(actual == expected)
                    #expect(!configurationListsItAfter)
                    #expect(!drawer.globalPlugins.contains { $0.id == NetworkPlugin().id })
                    #expect(logAfterUninstall == 0)
                    #expect(!protocolTakesRequests)
                    #expect(afterSecondUninstall == expected)
                    #expect(loggedAfterReinstall == ["reinstalled.invalid"])
                    #expect(zip(reinstalled, expected).allSatisfy { $0 != $1 })
                    #expect(afterLastUninstall == expected)
                }
                try await uninstallThenReinstall()
            }
        }

        @Test("A getter other code swapped in on top stays after the uninstall, and the plugin's code under it adds nothing then")
        func swizzleOnTopIsLeftInPlace() async {
            await #expect(processExitsWith: .success) {
                useHomeFolderOfItsOwn()
                @MainActor
                func swapOnTop() throws -> IMP {
                    let getter = try #require(
                        class_getInstanceMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.protocolClasses))
                    )
                    let onTop = try #require(
                        class_getInstanceMethod(URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.onTopProtocolClasses))
                    )
                    method_exchangeImplementations(getter, onTop)
                    return method_getImplementation(getter)
                }

                @MainActor
                func currentGetter() throws -> IMP {
                    try method_getImplementation(#require(class_getInstanceMethod(
                        URLSessionConfiguration.self, #selector(getter: URLSessionConfiguration.protocolClasses)
                    )))
                }

                @MainActor
                func listsProtocol() -> Bool {
                    URLSessionConfiguration.default.protocolClasses?.contains { $0 == DebugNetworkProtocol.self } ?? false
                }

                @MainActor
                func leaveInPlace() async throws {
                    let suite = "NetworkUninstallExitTests.\(UUID().uuidString)"
                    let defaults = try #require(UserDefaults(suiteName: suite))
                    defer { defaults.removePersistentDomain(forName: suite) }
                    let drawer = DebugDrawer(defaults: defaults)
                    drawer.installNetwork(sessions: .off)
                    let expected = try swapOnTop()

                    drawer.unregisterGlobal(id: NetworkPlugin().id)
                    let actual = try currentGetter()
                    let listsItWhileLeftInPlace = listsProtocol()
                    drawer.installNetwork(sessions: .off)
                    let listsItReinstalled = listsProtocol()
                    let getterReinstalled = try currentGetter()
                    drawer.unregisterGlobal(id: NetworkPlugin().id)

                    #expect(actual == expected)
                    #expect(!listsItWhileLeftInPlace)
                    #expect(listsItReinstalled)
                    #expect(getterReinstalled == expected)
                    #expect(!listsProtocol())
                }
                try await leaveInPlace()
            }
        }
    }
#endif
