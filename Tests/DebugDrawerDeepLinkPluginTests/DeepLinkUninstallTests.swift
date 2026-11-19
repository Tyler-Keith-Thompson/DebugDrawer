#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerDeepLinkPlugin
    import Foundation
    import Testing

    // Each test's drawer keeps its defaults in a suite of its own, which the plugin's install hands
    // the model as its history store; the model's opener is a fake, so nothing opens.
    @MainActor
    @Suite("Deep Link Tester forgets the last outcome once removed from every drawer, keeping the history", .timeLimit(.minutes(1)))
    struct DeepLinkUninstallTests {
        @Test("Unregistering removes the plugin and forgets the outcome; the history stays in memory and the defaults")
        func disappearsFromTheDrawer() async throws {
            let name = "DeepLinkUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let drawer = DebugDrawer(defaults: defaults)
            let model = DeepLinkModel(system: FakeSystemURLOpening(), store: FakeDeepLinkHistoryStore())
            let sut = DeepLinkPlugin(
                model: model, configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(), openURL: nil)
            )
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = transport.snapshots()
            let url = try #require(URL(string: "shop://orders/42"))
            drawer.registerGlobal(sut)
            transport.send(DeepLinkCommand(.open(url)))
            for await snapshot in snapshots where snapshot.outcome != nil {
                break
            }
            let outcomeWhileInstalled = model.snapshot.outcome

            drawer.unregisterGlobal(id: sut.id)

            #expect(outcomeWhileInstalled == .opened(url.absoluteString))
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(model.snapshot.outcome == nil)
            #expect(model.snapshot.history == [url.absoluteString])
            #expect(defaults.stringArray(forKey: _DeepLinkHistoryStore.historyKey) == [url.absoluteString])
        }

        @Test("Uninstalling twice is harmless, and a plugin registered again opens URLs again")
        func uninstallTwiceThenReinstall() async throws {
            let name = "DeepLinkUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            let drawer = DebugDrawer(defaults: defaults)
            let model = DeepLinkModel(system: FakeSystemURLOpening(), store: FakeDeepLinkHistoryStore())
            let sut = DeepLinkPlugin(
                model: model, configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(), openURL: nil)
            )
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = transport.snapshots()
            let url = try #require(URL(string: "shop://cart"))
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)
            transport.send(DeepLinkCommand(.open(url)))
            for await snapshot in snapshots where snapshot.outcome != nil {
                break
            }

            #expect(model.snapshot.outcome == .opened(url.absoluteString))
        }

        @Test("Installed in two drawers, the outcome stays until the second removes the plugin")
        func installCounting() async throws {
            let firstName = "DeepLinkUninstallTests.\(UUID().uuidString)"
            let secondName = "DeepLinkUninstallTests.\(UUID().uuidString)"
            let firstDefaults = try #require(UserDefaults(suiteName: firstName))
            let secondDefaults = try #require(UserDefaults(suiteName: secondName))
            defer {
                firstDefaults.removePersistentDomain(forName: firstName)
                secondDefaults.removePersistentDomain(forName: secondName)
            }
            let first = DebugDrawer(defaults: firstDefaults)
            let second = DebugDrawer(defaults: secondDefaults)
            let model = DeepLinkModel(system: FakeSystemURLOpening(), store: FakeDeepLinkHistoryStore())
            let sut = DeepLinkPlugin(
                model: model, configuration: DeepLinkConfiguration(presets: [], delivery: FakeUserActivityDelivering(), openURL: { _ in true })
            )
            let transport = DebugDrawerPluginTransport.direct(to: model)
            let snapshots = transport.snapshots()
            let url = try #require(URL(string: "shop://orders/1"))
            first.registerGlobal(sut)
            second.registerGlobal(sut)
            transport.send(DeepLinkCommand(.open(url)))
            for await snapshot in snapshots where snapshot.outcome != nil {
                break
            }

            first.unregisterGlobal(id: sut.id)
            let outcomeInOne = model.snapshot.outcome
            first.unregisterGlobal(id: sut.id)
            let outcomeAfterRepeat = model.snapshot.outcome
            second.unregisterGlobal(id: sut.id)

            #expect(outcomeInOne == .handled(url.absoluteString))
            #expect(outcomeAfterRepeat == .handled(url.absoluteString))
            #expect(model.snapshot.outcome == nil)
            #expect(model.snapshot.history == [url.absoluteString])
        }

        @Test("Installing hands the model the plugin's presets and the history kept in that drawer's defaults")
        func installConfiguresTheModel() throws {
            let name = "DeepLinkUninstallTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: name))
            defer { defaults.removePersistentDomain(forName: name) }
            defaults.set(["shop://kept"], forKey: _DeepLinkHistoryStore.historyKey)
            let drawer = DebugDrawer(defaults: defaults)
            let preset = try DeepLinkPreset("Cart", url: #require(URL(string: "shop://cart")))
            let model = DeepLinkModel(system: FakeSystemURLOpening(), store: FakeDeepLinkHistoryStore())
            let sut = DeepLinkPlugin(
                model: model, configuration: DeepLinkConfiguration(presets: [preset], delivery: FakeUserActivityDelivering(), openURL: nil)
            )
            let presetsBefore = model.snapshot.presets

            drawer.registerGlobal(sut)

            let actual = model.snapshot
            drawer.unregisterGlobal(id: sut.id)
            #expect(presetsBefore != [preset])
            #expect(actual.presets == [preset])
            #expect(actual.history == ["shop://kept"])
        }
    }
#endif
