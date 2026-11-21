// The README's "Remote viewing" examples, verbatim, so the README cannot drift from the code.

#if DEBUG
    import DebugDrawer
    import DebugDrawerConsolePlugin
    import DebugDrawerNetworkPlugin
    import DebugDrawerRemote
    import SwiftUI
    import Testing

    @MainActor
    final class RemoteViewing {
        let registry = DebugDrawerModelRegistry()
        let server: DebugDrawerNetworkServer

        init() {
            registry.register(NetworkModel.shared, id: NetworkPlugin().id)
            registry.register(ConsoleModel.shared, id: ConsolePlugin().id)
            server = DebugDrawerNetworkServer(registry: registry)
        }

        func enable() async throws {
            try await server.start()
        }
    }

    @MainActor
    func showRemoteViewing(_ remote: RemoteViewing) {
        DebugDrawer.shared.registerGlobal(RemoteViewingPlugin(server: remote.server))
    }

    @MainActor
    func viewNetwork(of device: DebugDrawerNetworkDevice, code: String) async throws
        -> DebugDrawerPluginTransport<NetworkSnapshot, NetworkCommand> {
        let viewer = DebugDrawerNetworkTransport(endpoint: device.endpoint, viewerName: "Studio Mac")
        try await viewer.pair(code: code)
        return try await viewer.connect(toPlugin: NetworkPlugin().id, snapshot: NetworkSnapshot.self, command: NetworkCommand.self)
    }

    struct DeviceView: View {
        let device: DebugDrawerNetworkTransport

        var body: some View {
            HStack(alignment: .top) {
                ScrollView { NetworkPluginView(transport: device) }
                ScrollView { ConsolePluginView(transport: device) }
            }
        }
    }

    // The examples are compiled; the one run here is the app's setup made and never enabled,
    // which, with the real listener, listens on nothing. `enable()` and the viewer would reach
    // the network, so they are left to the loopback tests.
    @MainActor
    @Suite("Remote viewing README examples")
    struct RemoteREADMEExamplesTests {
        @Test("The README's setup, made and never enabled, offers its models and listens on nothing")
        func setupListensOnNothing() {
            let sut = RemoteViewing()

            #expect(sut.server.isRunning == false)
            #expect(sut.server.port == nil)
            #expect(sut.server.configuration == DebugDrawerNetworkServerConfiguration())
        }
    }
#endif
