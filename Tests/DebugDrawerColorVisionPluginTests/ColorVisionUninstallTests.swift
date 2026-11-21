#if DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerColorVisionPlugin
    import DebugDrawerTestSupport
    import Foundation
    import Testing

    @MainActor
    @Suite("Color Vision turns its simulation off once removed from every drawer")
    struct ColorVisionUninstallTests {
        private static func drawer() throws -> (DebugDrawer, () -> Void) {
            let suite = temporarySuiteName("ColorVisionUninstallTests")
            let defaults = try #require(UserDefaults(suiteName: suite))
            return (DebugDrawer(defaults: defaults), { defaults.removePersistentDomain(forName: suite) })
        }

        @Test("Unregistering removes the plugin and turns the simulation off")
        func disappearsFromTheDrawer() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let model = ColorVisionModel()
            let sut = ColorVisionPlugin(model: model)
            drawer.registerGlobal(sut)
            model.simulation = .deuteranopia

            drawer.unregisterGlobal(id: sut.id)

            #expect(!drawer.globalPlugins.contains { $0.id == sut.id })
            #expect(model.simulation == nil)
        }

        @Test("A second drawer still holding the plugin keeps the simulation on")
        func twoDrawers() throws {
            let (first, cleanUpFirst) = try Self.drawer()
            let (second, cleanUpSecond) = try Self.drawer()
            defer {
                cleanUpFirst()
                cleanUpSecond()
            }
            let model = ColorVisionModel()
            let sut = ColorVisionPlugin(model: model)
            first.registerGlobal(sut)
            second.registerGlobal(sut)
            model.simulation = .grayscale

            first.unregisterGlobal(id: sut.id)
            let whileTheSecondHoldsIt = model.simulation
            second.unregisterGlobal(id: sut.id)

            #expect(whileTheSecondHoldsIt == .grayscale)
            #expect(model.simulation == nil)
        }

        @Test("Uninstalling twice is harmless, and a plugin registered again simulates again")
        func uninstallTwiceThenReinstall() throws {
            let (drawer, cleanUp) = try Self.drawer()
            defer { cleanUp() }
            let model = ColorVisionModel()
            let sut = ColorVisionPlugin(model: model)
            drawer.registerGlobal(sut)
            drawer.unregisterGlobal(id: sut.id)

            sut.uninstall(from: drawer)
            drawer.registerGlobal(sut)
            model.toggle(.protanopia)

            #expect(model.simulation == .protanopia)
            #expect(drawer.globalPlugins.contains { $0.id == sut.id })
        }
    }
#endif
