#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerDesignOverlayPlugin
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @MainActor
    @Suite("Design Overlay takes its mockup off the app once removed from every drawer")
    struct DesignOverlayUninstallTests {
        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = temporarySuiteName("DesignOverlayUninstallTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        @Test("Unregistering removes the plugin, ends Move and drops the mockup, leaving the saved mockup and saving no settings")
        func disappearsFromTheDrawer() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let storage = FakeMockupStorage()
            let model = DesignOverlayModel(storage: storage)
            let sut = DesignOverlayPlugin(model: model)
            drawer.registerGlobal(sut)
            model.open(MockupFixture.png(width: 64, height: 32))
            model.isMoving = true
            let movingWhileInstalled = model.isMoving
            let settingsSavesBefore = storage.settingsSaves

            drawer.unregisterGlobal(id: sut.id)

            #expect(movingWhileInstalled)
            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(!model.isMoving)
            #expect(model.mockup == nil)
            #expect(storage.mockup != nil)
            #expect(storage.settingsSaves == settingsSavesBefore)
        }

        @Test("Installing again over the same model shows the saved mockup again")
        func reinstallLoadsTheSavedMockup() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let storage = FakeMockupStorage()
            let model = DesignOverlayModel(storage: storage)
            let sut = DesignOverlayPlugin(model: model)
            drawer.registerGlobal(sut)
            model.open(MockupFixture.png(width: 64, height: 32))
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            model.load()
            drawer.registerGlobal(sut)

            #expect(model.mockup?.pixelSize == CGSize(width: 64, height: 32))
            #expect(model.settings.isVisible)
        }
    }
#endif
