// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerColorVisionPlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ColorVisionViewTests {
        @Test("Off: the picker offers Off and each simulation in order, and the row says the app keeps its colors")
        func off() throws {
            let sut = ColorVisionView(simulation: .constant(nil))
            // The picker's own label, which the row hides, comes last.
            let expectedOptions = ["Off", "Protanopia", "Deuteranopia", "Tritanopia", "Grayscale", "Simulate"]

            let options = try sut.inspect().find(ViewType.Picker.self).findAll(ViewType.Text.self).map { try $0.string() }
            let summary = try sut.inspect().find(text: "The app's own colors.").string()

            #expect(options == expectedOptions)
            #expect(summary == "The app's own colors.")
        }

        @Test("The footer names the Mac's own color filters, and where they are, for the whole screen")
        func systemColorFilters() throws {
            let sut = ColorVisionView(simulation: .constant(nil))
            let expected = "For the whole screen, AppKit and UIKit views too: System Settings › Accessibility › Display › Color filters."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
        }

        @Test("Picking a simulation sets it, and picking Off clears it")
        func picking() throws {
            var simulation: ColorVision.Simulation?
            let binding = Binding(get: { simulation }, set: { simulation = $0 })
            let sut = ColorVisionView(simulation: binding)

            try sut.inspect().find(ViewType.Picker.self).select(value: ColorVision.Simulation?.some(.tritanopia))
            let picked = simulation
            try sut.inspect().find(ViewType.Picker.self).select(value: ColorVision.Simulation?.none)

            #expect(picked == .tritanopia)
            #expect(simulation == nil)
        }

        @Test("The row describes the simulation picked", arguments: ColorVision.Simulation.allCases)
        func summary(simulation: ColorVision.Simulation) throws {
            let sut = ColorVisionView(simulation: .constant(simulation))

            let actual = try sut.inspect().find(text: simulation.summary).string()

            #expect(actual == simulation.summary)
        }

        @Test("The header names the simulation on, and shows nothing while off")
        func header() throws {
            let on = ColorVisionHeaderReadout(simulation: .deuteranopia)
            let off = ColorVisionHeaderReadout(simulation: nil)

            let actual = try on.inspect().find(ViewType.Text.self).string()

            #expect(actual == "Deuteranopia")
            #expect(throws: (any Error).self) { try off.inspect().find(ViewType.Text.self) }
        }

        @Test("The HUD names the simulation on, or Simulation Off, says what a tap switches to, and a tap cycles")
        func hud() throws {
            var cycled = 0
            let on = ColorVisionHUDButton(simulation: .grayscale, cycle: { cycled += 1 })
            let off = ColorVisionHUDButton(simulation: nil, cycle: {})

            try on.inspect().find(ViewType.Button.self).tap()
            let onTitle = try on.inspect().find(ViewType.Label.self).title().text().string()
            let onLabel = try on.inspect().find(ViewType.Button.self).accessibilityLabel().string()
            let onHint = try on.inspect().find(ViewType.Button.self).accessibilityHint().string()
            let offTitle = try off.inspect().find(ViewType.Label.self).title().text().string()
            let offHint = try off.inspect().find(ViewType.Button.self).accessibilityHint().string()

            #expect(cycled == 1)
            #expect(onTitle == "Grayscale")
            #expect(onLabel == "Color vision simulation: Grayscale")
            #expect(onHint == "Switches to Off")
            #expect(offTitle == "Simulation Off")
            #expect(offHint == "Switches to Protanopia")
        }

        @Test("The plugin's view shows the model's simulation and picks into it")
        func pluginView() throws {
            let model = ColorVisionModel()
            model.simulation = .protanopia
            let sut = ColorVisionPluginView(model: model)

            let summary = try sut.inspect().find(text: ColorVision.Simulation.protanopia.summary).string()
            try sut.inspect().find(ViewType.Picker.self).select(value: ColorVision.Simulation?.some(.grayscale))

            #expect(summary == ColorVision.Simulation.protanopia.summary)
            #expect(model.simulation == .grayscale)
        }
    }
#endif
