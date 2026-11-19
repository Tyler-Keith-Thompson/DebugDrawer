#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import Testing

    // `installDeepLink` registers a plugin over DeepLinkModel.shared, which takes the install's
    // presets, handlers and drawer defaults, so the tests that call it run one at a time, here and
    // in the suites nested in extensions (the README's). Each passes an openURL handler, so nothing
    // reaches the system, and keeps its drawer, with defaults of its own, installed until the
    // outcome lands.
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct DeepLinkSharedModelTests {
        @Test("installDeepLink hands the shared model the presets and the openURL handler, and an opened URL reaches the handler")
        func installPassesPresetsAndHandler() async throws {
            var received: [URL] = []
            let presets = try [DeepLinkPreset("Order 42", url: #require(URL(string: "myapp://orders/42")))]
            let url = try #require(URL(string: "myapp://orders/42"))
            let suite = "DeepLinkSharedModelTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let transport = DebugDrawerPluginTransport.direct(to: DeepLinkModel.shared)
            let snapshots = transport.snapshots()

            drawer.installDeepLink(presets: presets, openURL: { received.append($0); return true })
            transport.send(DeepLinkCommand(.open(url)))
            var actual: DeepLinkSnapshot?
            for await snapshot in snapshots where snapshot.outcome == .handled("myapp://orders/42") {
                actual = snapshot
                break
            }
            let installed = drawer.globalPlugins.contains { $0.id == "DeepLinkPlugin" }
            drawer.unregisterGlobal(id: "DeepLinkPlugin")

            #expect(installed)
            #expect(actual?.presets == presets)
            #expect(received == [url])
        }

        @Test("installDeepLink keeps the history in the drawer's own defaults, not the shared drawer's suite")
        func installKeepsHistoryInTheDrawersDefaults() async throws {
            let url = try #require(URL(string: "myapp://orders/43"))
            let suite = "DeepLinkSharedModelTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let drawer = DebugDrawer(defaults: defaults)
            let transport = DebugDrawerPluginTransport.direct(to: DeepLinkModel.shared)
            let snapshots = transport.snapshots()
            let expected = ["myapp://orders/43"]

            drawer.installDeepLink(presets: [], openURL: { _ in true })
            transport.send(DeepLinkCommand(.open(url)))
            for await snapshot in snapshots where snapshot.outcome == .handled("myapp://orders/43") {
                break
            }
            drawer.unregisterGlobal(id: "DeepLinkPlugin")

            #expect(defaults.stringArray(forKey: _DeepLinkHistoryStore.historyKey) == expected)
        }
    }
#endif
