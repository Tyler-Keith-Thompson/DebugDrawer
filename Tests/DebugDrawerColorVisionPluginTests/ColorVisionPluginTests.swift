#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerColorVisionPlugin
    import Testing

    @MainActor
    @Suite
    struct ColorVisionPluginTests {
        @Test("The plugin is Color Vision, in Interface, with a HUD readout and a header accessory")
        func identity() {
            let sut = ColorVisionPlugin(model: ColorVisionModel())

            #expect(sut.id == "ColorVisionPlugin")
            #expect(sut.title == "Color Vision")
            #expect(sut.category == "Interface")
            #expect(sut.icon == "eye")
            #expect(AnyDebugDrawerPlugin(sut).hasHUD)
            #expect(AnyDebugDrawerPlugin(sut).headerAccessory != nil)
        }

        @Test("The drawer's search turns each simulation on and off, found by \"color blind\" and its name, and turns them all off")
        func actions() throws {
            let model = ColorVisionModel()
            let sut = ColorVisionPlugin(model: model)
            let expectedTitles = [
                "Simulate protanopia", "Simulate deuteranopia", "Simulate tritanopia", "Simulate grayscale",
                "Turn off color vision simulation"
            ]
            let deuteranopia = try #require(sut.actions.first { $0.keywords.contains("deuteranopia") })
            let off = try #require(sut.actions.first { $0.keywords.contains("off") })

            deuteranopia.perform()
            let afterOn = model.simulation
            deuteranopia.perform()
            let afterAgain = model.simulation
            deuteranopia.perform()
            off.perform()

            #expect(sut.actions.map(\.title) == expectedTitles)
            #expect(sut.actions.allSatisfy { $0.keywords.contains("blind") })
            #expect(afterOn == .deuteranopia)
            #expect(afterAgain == nil)
            #expect(model.simulation == nil)
        }

        @Test("The model starts off, cycles through each simulation and back, and a toggle of another switches to it")
        func model() {
            let sut = ColorVisionModel()
            let initial = sut.simulation

            sut.cycle()
            let first = sut.simulation
            sut.toggle(.tritanopia)
            let switched = sut.simulation
            sut.cycle()
            sut.cycle()
            let wrapped = sut.simulation

            #expect(initial == nil)
            #expect(first == .protanopia)
            #expect(switched == .tritanopia)
            #expect(wrapped == nil)
        }
    }
#endif
