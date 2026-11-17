// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerDesignOverlayPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct DesignOverlayViewTests {
        @Test("Before a mockup is picked: where to pick one, Choose File… and Paste, and no settings or Clear")
        func empty() throws {
            var pasted = 0
            let sources = MockupSources(open: { _ in }, openFile: { _ in }, paste: { pasted += 1 }, fail: { _ in })
            let sut = DesignOverlayView(
                mockup: nil, failure: nil, windowWidth: 800, settings: .constant(DesignOverlaySettings()), isMoving: .constant(false),
                sources: sources, clear: {}
            )

            try sut.inspect().find(button: "Paste").tap()
            let title = try sut.inspect().find(text: "No mockup").string()
            let chooseFile = try sut.inspect().find(button: "Choose File…").labelView().text().string()

            #expect(title == "No mockup")
            #expect(chooseFile == "Choose File…")
            #expect(pasted == 1)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Clear") }
            #expect(throws: (any Error).self) { try sut.inspect().find(text: "Opacity") }
        }

        @Test("A mockup shows its pixel size and the size it is drawn at, the inferred scale named, with Clear")
        func summary() throws {
            let mockup = try Mockup(data: MockupFixture.png(width: 1290, height: 2796))
            var cleared = 0
            let sut = DesignOverlayView(
                mockup: mockup, failure: nil, windowWidth: 430, settings: .constant(DesignOverlaySettings()), isMoving: .constant(false),
                sources: .none, clear: { cleared += 1 }
            )
            let expectedSize = "1290 × 2796 px"
            let expectedDrawn = "Drawn at @3x (automatic): 430 × 932 pt"

            try sut.inspect().find(button: "Clear").tap()
            let size = try sut.inspect().find(text: expectedSize).string()
            let drawn = try sut.inspect().find(text: expectedDrawn).string()

            #expect(size == expectedSize)
            #expect(drawn == expectedDrawn)
            #expect(cleared == 1)
        }

        @Test("Fit Width says so, with the size it is drawn at; before the window is laid out only the scale shows")
        func summaryFitWidth() throws {
            let mockup = try Mockup(data: MockupFixture.png(width: 800, height: 400))
            var settings = DesignOverlaySettings()
            settings.scale = .fitWidth
            let laidOut = DesignOverlayView(
                mockup: mockup, failure: nil, windowWidth: 400, settings: .constant(settings), isMoving: .constant(false),
                sources: .none, clear: {}
            )
            let notLaidOut = DesignOverlayView(
                mockup: mockup, failure: nil, windowWidth: nil, settings: .constant(settings), isMoving: .constant(false),
                sources: .none, clear: {}
            )

            let fit = try laidOut.inspect().find(text: "Drawn to fit the width: 400 × 200 pt").string()
            let unknown = try notLaidOut.inspect().find(text: "Drawn at Fit Width").string()

            #expect(fit == "Drawn to fit the width: 400 × 200 pt")
            #expect(unknown == "Drawn at Fit Width")
        }

        @Test("Show, the opacity slider, the blend and the scale pickers and the steppers change the settings")
        func controls() throws {
            let mockup = try Mockup(data: MockupFixture.png(width: 100, height: 100))
            var settings = DesignOverlaySettings()
            let binding = Binding(get: { settings }, set: { settings = $0 })
            func sut() -> DesignOverlayView {
                DesignOverlayView(
                    mockup: mockup, failure: nil, windowWidth: 100, settings: binding, isMoving: .constant(false), sources: .none, clear: {}
                )
            }

            try sut().inspect().find(ViewType.Toggle.self, where: { try $0.labelView().text().string() == "Show Mockup" }).tap()
            try sut().inspect().find(ViewType.Slider.self).setValue(0.8)
            try sut().inspect().find(ViewType.Picker.self, where: { try $0.labelView().text().string() == "Blend" })
                .select(value: MockupBlend.difference)
            try sut().inspect().find(ViewType.Picker.self, where: { try $0.labelView().text().string() == "Scale" }).select(value: MockupScale.at2x)
            try sut().inspect().findAll(ViewType.Stepper.self)[0].increment()
            try sut().inspect().findAll(ViewType.Stepper.self)[1].decrement()

            #expect(!settings.isVisible)
            #expect(settings.opacity == 0.8)
            #expect(settings.blend == .difference)
            #expect(settings.scale == .at2x)
            #expect(settings.offset == CGSize(width: 1, height: -1))
        }

        @Test("The opacity and the offsets read beside their controls")
        func readouts() throws {
            let mockup = try Mockup(data: MockupFixture.png(width: 100, height: 100))
            var settings = DesignOverlaySettings()
            settings.opacity = 0.35
            settings.offset = CGSize(width: 12, height: -4)
            let sut = DesignOverlayView(
                mockup: mockup, failure: nil, windowWidth: 100, settings: .constant(settings), isMoving: .constant(false),
                sources: .none, clear: {}
            )

            let opacity = try sut.inspect().find(text: "35%").string()
            let offsetX = try sut.inspect().find(text: "12 pt").string()
            let offsetY = try sut.inspect().find(text: "-4 pt").string()

            #expect(opacity == "35%")
            #expect(offsetX == "12 pt")
            #expect(offsetY == "-4 pt")
        }

        @Test("Move by Dragging turns Move on, and is disabled while the mockup is hidden")
        func move() throws {
            let mockup = try Mockup(data: MockupFixture.png(width: 100, height: 100))
            var isMoving = false
            let binding = Binding(get: { isMoving }, set: { isMoving = $0 })
            var hidden = DesignOverlaySettings()
            hidden.isVisible = false
            let shown = DesignOverlayView(
                mockup: mockup, failure: nil, windowWidth: 100, settings: .constant(DesignOverlaySettings()), isMoving: binding,
                sources: .none, clear: {}
            )
            let whileHidden = DesignOverlayView(
                mockup: mockup, failure: nil, windowWidth: 100, settings: .constant(hidden), isMoving: binding, sources: .none, clear: {}
            )

            try shown.inspect().find(ViewType.Toggle.self, where: { try $0.labelView().text().string() == "Move by Dragging" }).tap()
            let isDisabled = try whileHidden.inspect().find(DebugDrawerRow<EmptyView, Toggle<Text>>.self, where: { row in
                try row.find(text: "Move by Dragging").string() == "Move by Dragging"
            }).isDisabled()

            #expect(isMoving)
            #expect(isDisabled)
        }

        @Test("Reset Position shows once the mockup is moved, and puts it back in the corner")
        func resetPosition() throws {
            let mockup = try Mockup(data: MockupFixture.png(width: 100, height: 100))
            var settings = DesignOverlaySettings()
            let binding = Binding(get: { settings }, set: { settings = $0 })
            func sut() -> DesignOverlayView {
                DesignOverlayView(
                    mockup: mockup, failure: nil, windowWidth: 100, settings: binding, isMoving: .constant(false), sources: .none, clear: {}
                )
            }
            let unmoved = Result { try sut().inspect().find(button: "Reset Position") }
            settings.offset = CGSize(width: 5, height: 9)

            try sut().inspect().find(button: "Reset Position").tap()

            #expect(throws: (any Error).self) { try unmoved.get() }
            #expect(settings.offset == .zero)
        }

        @Test("A mockup that wasn't shown says why as an error; one that wasn't saved as a warning")
        func failures() throws {
            let notShown = DesignOverlayView(
                mockup: nil, failure: .notAnImage, windowWidth: nil, settings: .constant(DesignOverlaySettings()), isMoving: .constant(false),
                sources: .none, clear: {}
            )
            let notSaved = DesignOverlayView(
                mockup: nil, failure: .notSaved, windowWidth: nil, settings: .constant(DesignOverlaySettings()), isMoving: .constant(false),
                sources: .none, clear: {}
            )

            let message = try notShown.inspect().find(text: "That isn't an image this device can read.").string()
            let shownTitle = try notShown.inspect().find(DebugDrawerIssueRow<Text, EmptyView>.self).actualView().title
            let savedTitle = try notSaved.inspect().find(DebugDrawerIssueRow<Text, EmptyView>.self).actualView().title
            let savedSeverity = try notSaved.inspect().find(DebugDrawerIssueRow<Text, EmptyView>.self).actualView().severity

            #expect(message == "That isn't an image this device can read.")
            #expect(shownTitle == "Not shown")
            #expect(savedTitle == "Not saved")
            #expect(savedSeverity == .warning)
        }

        @Test("Choose File… opens the file importer, which the view keeps open in its own state")
        func chooseFile() async throws {
            let sut = DesignOverlayView(
                mockup: nil, failure: nil, windowWidth: nil, settings: .constant(DesignOverlaySettings()), isMoving: .constant(false),
                sources: .none, clear: {}
            )
            var before = true
            var after = false

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    before = try view.actualView().isImporting
                    try view.find(button: "Choose File…").tap()
                }
                try await sut.inspection.inspect { view in
                    after = try view.actualView().isImporting
                }
            }

            #expect(!before)
            #expect(after)
        }

        @Test("The HUD hides a shown mockup, shows a hidden one, ends Move with Done, and does nothing before a mockup")
        func hud() throws {
            var toggles = 0
            var ends = 0
            func sut(_ state: DesignOverlayStatus) -> DesignOverlayHUDButtons {
                DesignOverlayHUDButtons(state: state, toggleVisibility: { toggles += 1 }, endMoving: { ends += 1 })
            }

            try sut(.showing(opacity: "50%", blend: .normal)).inspect().find(ViewType.Button.self).tap()
            try sut(.hidden).inspect().find(ViewType.Button.self).tap()
            try sut(.moving).inspect().find(ViewType.Button.self).tap()
            let showing = try sut(.showing(opacity: "50%", blend: .normal)).inspect().find(text: "Mockup 50%").string()
            let noMockup = try sut(.noMockup).inspect().find(text: "No mockup").string()

            #expect(toggles == 2)
            #expect(ends == 1)
            #expect(showing == "Mockup 50%")
            #expect(noMockup == "No mockup")
            #expect(throws: (any Error).self) { try sut(.noMockup).inspect().find(ViewType.Button.self) }
        }

        @Test("The header reads the status, and nothing before a mockup")
        func header() throws {
            let difference = try DesignOverlayHeaderReadout(state: .showing(opacity: "70%", blend: .difference)).inspect().text().string()
            let moving = try DesignOverlayHeaderReadout(state: .moving).inspect().text().string()

            #expect(difference == "70% · Difference")
            #expect(moving == "Moving")
            #expect(throws: (any Error).self) { try DesignOverlayHeaderReadout(state: .noMockup).inspect().text() }
        }

        @Test("The Move bar says what a drag does and where the mockup is, and Done ends Move")
        func moveBar() throws {
            var done = 0
            let sut = MoveModeBar(offset: CGSize(width: 12, height: -4), done: { done += 1 })

            try sut.inspect().find(button: "Done").tap()
            let offset = try sut.inspect().find(text: "x 12  y -4").string()
            let prompt = try sut.inspect().find(text: "Drag to move the mockup").string()

            #expect(done == 1)
            #expect(offset == "x 12  y -4")
            #expect(prompt == "Drag to move the mockup")
        }

        @Test("The mockup takes no hits while Move is off, takes them while it is on, and is drawn at its opacity and blend")
        func layer() throws {
            let mockup = try Mockup(data: MockupFixture.png(width: 100, height: 100))
            var settings = DesignOverlaySettings()
            settings.opacity = 0.4
            settings.blend = .difference
            let still = DesignOverlayLayer(mockup: mockup, settings: settings, isMoving: false, move: { _ in })
            let moving = DesignOverlayLayer(mockup: mockup, settings: settings, isMoving: true, move: { _ in })

            let stillHits = try still.inspect().geometryReader().allowsHitTesting()
            let movingHits = try moving.inspect().geometryReader().allowsHitTesting()
            let image = try still.inspect().find(ViewType.Image.self)

            #expect(!stillHits)
            #expect(movingHits)
            #expect(try image.opacity() == 0.4)
            #expect(try image.blendMode() == .difference)
            #expect(try still.inspect().geometryReader().accessibilityHidden())
        }
    }
#endif
