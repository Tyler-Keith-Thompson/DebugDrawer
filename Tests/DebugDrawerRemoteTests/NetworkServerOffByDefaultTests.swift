#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerRemote
    import Foundation
    import Testing

    // Off by default, proved through the server's and browser's seams: a fake listener and a fake
    // browser record every call, so the tests see that nothing listens, advertises or browses until
    // the app asks, and what would be advertised, without any of it happening on this Mac.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct NetworkServerOffByDefaultTests {
        @Test("A server the app made, with models registered, neither listens nor advertises until it is started")
        func nothingListensBeforeStart() {
            let listener = FakeConnectionListener()
            let registry = DebugDrawerModelRegistry()
            registry.register(CounterModel(), id: "Counter")

            let sut = DebugDrawerNetworkServer(registry: registry, configuration: .init(), listener: listener)

            #expect(listener.requests.isEmpty)
            #expect(sut.isRunning == false)
            #expect(sut.port == nil)
            #expect(sut.pairingRequests.isEmpty)
        }

        @Test("Started with the default configuration, the server listens once on every interface and advertises the app's Bonjour service")
        func startListensAndAdvertises() async throws {
            let listener = FakeConnectionListener(port: 52_100)
            let sut = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: .init(), listener: listener)
            let expected = ListenerRequest(
                port: nil,
                loopbackOnly: false,
                advertisement: .init(name: nil, txtRecord: DebugDrawerBonjourService.currentTXTRecord())
            )

            try await sut.start()
            try await sut.start()

            #expect(listener.requests == [expected])
            #expect(sut.port == 52_100)
            #expect(sut.isRunning)
        }

        @Test("Started with .loopback, the server listens on 127.0.0.1 only and advertises nothing")
        func loopbackAdvertisesNothing() async throws {
            let listener = FakeConnectionListener()
            let sut = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: .loopback, listener: listener)
            let expected = ListenerRequest(port: nil, loopbackOnly: true, advertisement: nil)

            try await sut.start()

            #expect(listener.requests == [expected])
        }

        @Test("A named service on a fixed port asks for that name and port")
        func namedServiceOnFixedPort() async throws {
            let listener = FakeConnectionListener(port: 9_001)
            let configuration = DebugDrawerNetworkServerConfiguration(serviceName: "QA iPad", port: 9_001)
            let sut = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: configuration, listener: listener)

            try await sut.start()

            let actual = try #require(listener.requests.first)
            #expect(actual.port == 9_001)
            #expect(actual.advertisement?.name == "QA iPad")
        }

        @Test("Stopped, the server stops listening and advertising, and can start again")
        func stopCancelsTheListener() async throws {
            let listener = FakeConnectionListener()
            let sut = DebugDrawerNetworkServer(registry: DebugDrawerModelRegistry(), configuration: .init(), listener: listener)
            try await sut.start()

            sut.stop()
            let stoppedPort = sut.port
            try await sut.start()

            #expect(listener.cancelCount == 1)
            #expect(stoppedPort == nil)
            #expect(listener.requests.count == 2)
        }

        @Test("A browser the viewer made browses nothing until it is started")
        func browserIdleUntilStarted() {
            let browser = FakeServiceBrowser()

            let sut = DebugDrawerNetworkBrowser(browser: browser)

            #expect(browser.startCount == 0)
            #expect(sut.isBrowsing == false)
            #expect(sut.devices.isEmpty)
        }
    }
#endif
